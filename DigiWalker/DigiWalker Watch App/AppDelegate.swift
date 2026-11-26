import SwiftUI
import UserNotifications
import WatchKit

enum AppEnvironment {
    /// The watch app tests use the app as their host. Skipping system registrations keeps them from touching
    /// notifications or the refresh schedule.
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}

final class AppDelegate: NSObject, WKApplicationDelegate {
    /// Owned here because a background launch has no view.
    let game: WatchGameStore
    private let notificationDelegate = GrowthNotificationDelegate()

    override init() {
        // Tests host the real app: give the store inert dependencies so nothing touches HealthKit,
        // notifications, the refresh schedule or the real files.
        game = AppEnvironment.isRunningTests ? .inertForTestHost() : WatchGameStore(scheduler: RefreshScheduler())
        super.init()
    }

    func applicationDidFinishLaunching() {
        guard !AppEnvironment.isRunningTests else { return }
        UNUserNotificationCenter.current().delegate = notificationDelegate
        game.startObservingIfEnrolled()
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if task is WKApplicationRefreshBackgroundTask {
                // The settlement schedules the next refresh itself.
                let game = game
                let finish = BackgroundRun.run(
                    work: { await game.refresh() },
                    complete: { task.setTaskCompletedWithSnapshot(false) }
                )
                // The system may call this off the main actor, so the closure must not inherit MainActor isolation.
                task.expirationHandler = { @Sendable in
                    if Thread.isMainThread {
                        MainActor.assumeIsolated { finish() }
                    } else {
                        Task { @MainActor in finish() }
                    }
                }
            } else {
                // Snapshot and connectivity tasks carry nothing this app processes yet.
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
