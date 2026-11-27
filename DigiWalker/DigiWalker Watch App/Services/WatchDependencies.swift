import DigiWalkerCore
import Foundation
import HealthKit
import WatchKit

// Seams for WatchGameStore so serialization, event emission and failure handling can be tested with fakes.

protocol HealthReading {
    func requestAccess() async throws
    func reconciled(_ saved: GameState, through now: Date) async throws -> GameState
}

protocol StateStoring {
    func load() throws -> GameState?
    func save(_ value: GameState) throws
}

protocol SnapshotPublishing {
    func publish(_ snapshot: MonsterSnapshot)
    /// Sends the snapshot again even if the same revision went out before. For an ignored iPhone request: the
    /// iPhone may be waiting on a state change that already happened or never will.
    func republish(_ snapshot: MonsterSnapshot)
}

extension SnapshotPublishing {
    func republish(_ snapshot: MonsterSnapshot) { publish(snapshot) }
}

protocol GrowthAnnouncing {
    /// Foreground cue for a hatch or evolution.
    func playHaptic(for event: GrowthEvent)
    /// Background cue (local notification). Throws if it could not be delivered.
    func notify(_ event: GrowthEvent) async throws
    /// Asks for notification permission if undecided. Returns whether notifications are allowed.
    func requestPermission() async -> Bool
    /// Removes delivered and scheduled notifications with these identifiers (an event that is no longer true).
    func withdraw(identifiers: [String])
}

protocol PendingEventStoring {
    func load() throws -> [GrowthEvent]
    func save(_ events: [GrowthEvent]) throws
}

protocol RefreshScheduling {
    /// Called after every settlement attempt once the partner is enrolled.
    func scheduleNextRefresh()
}

protocol AppActivityProviding {
    var isActive: Bool { get }
}

extension HealthService: HealthReading {}
extension WatchSyncService: SnapshotPublishing {}
extension StateFile: StateStoring where Value == GameState {}

/// Undelivered hatches and evolutions, in their own small file so the growth state file stays untouched.
struct PendingEventFile: PendingEventStoring {
    private let file: StateFile<[GrowthEvent]>

    init(url: URL = URL.applicationSupportDirectory.appending(path: "pending-growth-events.json")) {
        file = StateFile(url: url)
    }

    func load() throws -> [GrowthEvent] { try file.load() ?? [] }
    func save(_ events: [GrowthEvent]) throws { try file.save(events) }
}

struct NoRefreshScheduler: RefreshScheduling {
    func scheduleNextRefresh() {
        // Used by tests and previews; the app uses RefreshScheduler.
    }
}

struct WatchAppActivity: AppActivityProviding {
    var isActive: Bool { WKApplication.shared().applicationState == .active }
}

/// Wakes the app when new step samples arrive. `complete` must be called exactly once per update.
protocol HealthObserving {
    func start(onUpdate: @escaping @Sendable (Error?, @escaping @Sendable () -> Void) -> Void)
    /// Registers background delivery again if an earlier attempt failed. Never installs a second query.
    func retryBackgroundDelivery()
}

/// HKObserverQuery on steps plus hourly background delivery. Registers at most one query.
@MainActor
final class HealthObserver: HealthObserving {
    private let store = HKHealthStore()
    private var query: HKObserverQuery?
    private var deliveryEnabled = false
    private var enablingDelivery = false
    private let type = HKQuantityType(.stepCount)

    func start(onUpdate: @escaping @Sendable (Error?, @escaping @Sendable () -> Void) -> Void) {
        guard query == nil, HKHealthStore.isHealthDataAvailable() else { return }
        let query = Self.makeQuery(type: type, onUpdate: onUpdate)
        self.query = query
        store.execute(query)
        retryBackgroundDelivery()
    }

    func retryBackgroundDelivery() {
        guard query != nil, !deliveryEnabled, !enablingDelivery else { return }
        enablingDelivery = true
        Self.enableDelivery(store: store, type: type) { [weak self] succeeded in
            Task { @MainActor in
                self?.enablingDelivery = false
                if succeeded { self?.deliveryEnabled = true }
            }
        }
    }

    /// HealthKit calls the completion on its own queue, so it is built outside any actor.
    private nonisolated static func enableDelivery(
        store: HKHealthStore, type: HKQuantityType, finished: @escaping @Sendable (Bool) -> Void
    ) {
        store.enableBackgroundDelivery(for: type, frequency: .hourly) { success, error in
            if let error { NSLog("DigiWalker: background delivery not enabled (%@)", error.localizedDescription) }
            finished(success && error == nil)
        }
    }

    /// The handler runs on a HealthKit queue, so it is built outside any actor and hops to the main actor itself.
    private nonisolated static func makeQuery(
        type: HKQuantityType,
        onUpdate: @escaping @Sendable (Error?, @escaping @Sendable () -> Void) -> Void
    ) -> HKObserverQuery {
        HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
            nonisolated(unsafe) let completion = completion
            onUpdate(error) { completion() }
        }
    }
}

// Inert stand-ins for the test host, which launches the real app.

struct InertHealth: HealthReading {
    func requestAccess() async throws {}
    func reconciled(_ saved: GameState, through now: Date) async throws -> GameState { saved }
}

final class MemoryStateFile: StateStoring {
    private var value: GameState?
    func load() throws -> GameState? { value }
    func save(_ value: GameState) throws { self.value = value }
}

final class MemoryPendingEvents: PendingEventStoring {
    private var events: [GrowthEvent] = []
    func load() throws -> [GrowthEvent] { events }
    func save(_ events: [GrowthEvent]) throws { self.events = events }
}

struct InertPublisher: SnapshotPublishing {
    func publish(_ snapshot: MonsterSnapshot) {}
}

struct InertAnnouncer: GrowthAnnouncing {
    func playHaptic(for event: GrowthEvent) {}
    func notify(_ event: GrowthEvent) async throws {}
    func requestPermission() async -> Bool { false }
    func withdraw(identifiers: [String]) {}
}

struct InertObserver: HealthObserving {
    func start(onUpdate: @escaping @Sendable (Error?, @escaping @Sendable () -> Void) -> Void) {}
    func retryBackgroundDelivery() {}
}

extension WatchGameStore {
    static func inertForTestHost() -> WatchGameStore {
        WatchGameStore(health: InertHealth(), file: MemoryStateFile(), sync: InertPublisher(),
                       announcer: InertAnnouncer(), scheduler: NoRefreshScheduler(),
                       activity: WatchAppActivity(), pending: MemoryPendingEvents(), observer: InertObserver(),
                       widget: InertWidgetPublisher(), wakeLog: MemoryBackgroundLog())
    }
}
