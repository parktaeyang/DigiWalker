import DigiWalkerCore
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
    /// Owned here too: requests from the iPhone must be received in a background launch, before any view exists.
    private let sync: WatchSyncService?
    private let notificationDelegate: GrowthNotificationDelegate

    override init() {
        // Tests host the real app: give the store inert dependencies so nothing touches HealthKit,
        // notifications, the refresh schedule or the real files.
        if AppEnvironment.isRunningTests {
            game = .inertForTestHost()
            sync = nil
        } else {
            let sync = WatchSyncService()
            game = WatchGameStore(sync: sync, scheduler: RefreshScheduler())
            self.sync = sync
        }
        notificationDelegate = GrowthNotificationDelegate(game: game)
        super.init()
    }

    func applicationDidFinishLaunching() {
        guard !AppEnvironment.isRunningTests else { return }
        UNUserNotificationCenter.current().delegate = notificationDelegate
        GrowthNotifier.registerCategories()
        let game = game
        sync?.onNewEggRequest = { request in await game.startNewEgg(target: request.targetMonsterId) }
        sync?.activate()
        game.startObservingIfEnrolled()
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if task is WKApplicationRefreshBackgroundTask {
                // The settlement schedules the next refresh itself.
                let game = game
                let finish = BackgroundRun.run(
                    work: { await game.refresh(wake: .refresh) },
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
            } else if task is WKWatchConnectivityRefreshBackgroundTask, let sync {
                // Delivery of a transferred request: activate the session, then finish once nothing is pending
                // and every received request has been applied (the request runs in the store's settlement chain).
                sync.activate()
                let finish = BackgroundRun.run(
                    work: {
                        // Two idle looks in a row, so a callback that is just about to arrive is not missed.
                        // Bounded (about the run timeout) so the loop stops even after the timeout completed the task.
                        var idle = 0
                        var looks = 0
                        while idle < 2, looks < 66, !Task.isCancelled {
                            try? await Task.sleep(for: .milliseconds(300))
                            idle = sync.isBusy ? 0 : idle + 1
                            looks += 1
                        }
                    },
                    complete: { task.setTaskCompletedWithSnapshot(false) }
                )
                task.expirationHandler = { @Sendable in
                    if Thread.isMainThread {
                        MainActor.assumeIsolated { finish() }
                    } else {
                        Task { @MainActor in finish() }
                    }
                }
            } else {
                // Snapshot tasks carry nothing this app processes yet.
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
