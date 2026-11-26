import DigiWalkerCore
import Foundation
import Testing
@testable import DigiWalker_Watch_App

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private struct TestFailure: Error {}

private final class FakeFile: StateStoring {
    var stored: GameState?
    var failSave = false
    var failLoad = false
    var saves = 0
    init(_ stored: GameState?) { self.stored = stored }
    func load() throws -> GameState? {
        if failLoad { throw TestFailure() }
        return stored
    }
    func save(_ value: GameState) throws {
        if failSave { throw TestFailure() }
        stored = value
        saves += 1
    }
}

/// Credits `steps` for the settlement day; a repeated reading adds nothing.
private final class FakeHealth: HealthReading {
    var steps = 600
    var running = 0
    var maxRunning = 0
    var calls = 0
    /// Returns the saved state untouched, as if the reading changed nothing.
    var passThrough = false
    /// While true, a read parks until `releaseReads()`.
    var holdReads = false
    private var readStarted = 0
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var parked: [CheckedContinuation<Void, Never>] = []

    func requestAccess() async throws {}

    func waitForReadToStart() async {
        if readStarted > 0 { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func releaseReads() {
        holdReads = false
        let waiting = parked
        parked = []
        waiting.forEach { $0.resume() }
    }

    func reconciled(_ saved: GameState, through now: Date) async throws -> GameState {
        calls += 1
        running += 1
        maxRunning = max(maxRunning, running)
        defer { running -= 1 }
        readStarted += 1
        let starting = startWaiters
        startWaiters = []
        starting.forEach { $0.resume() }
        if holdReads { await withCheckedContinuation { parked.append($0) } }
        // Let overlapping callers (if serialization were broken) run into each other.
        await Task.yield()
        if passThrough { return saved }
        var next = saved
        next.settle(day: now, steps: steps, distance: nil)
        return next
    }
}

private final class FakePending: PendingEventStoring {
    var stored: [GrowthEvent] = []
    var failSave = false
    var failLoad = false
    var saves = 0
    func load() throws -> [GrowthEvent] {
        if failLoad { throw TestFailure() }
        return stored
    }
    func save(_ events: [GrowthEvent]) throws {
        if failSave { throw TestFailure() }
        stored = events
        saves += 1
    }
}

private final class FakeSync: SnapshotPublishing {
    var published = 0
    func publish(_ snapshot: MonsterSnapshot) { published += 1 }
}

private final class FakeAnnouncer: GrowthAnnouncing {
    var haptics: [GrowthEvent] = []
    var notified: [GrowthEvent] = []
    var failNotify = false
    /// Runs inside notify(), i.e. at the moment the notification is being handed to the system.
    var onNotify: (() -> Void)?
    func playHaptic(for event: GrowthEvent) { haptics.append(event) }
    func notify(_ event: GrowthEvent) async throws {
        onNotify?()
        if failNotify { throw TestFailure() }
        notified.append(event)
    }
    var permissionGranted = true
    func requestPermission() async -> Bool { permissionGranted }
}

private final class FakeScheduler: RefreshScheduling {
    var scheduled = 0
    func scheduleNextRefresh() { scheduled += 1 }
}

private final class FakeObserver: HealthObserving {
    var starts = 0
    var deliveryRetries = 0
    func retryBackgroundDelivery() { deliveryRetries += 1 }
    var handler: (@Sendable (Error?, @escaping @Sendable () -> Void) -> Void)?
    func start(onUpdate: @escaping @Sendable (Error?, @escaping @Sendable () -> Void) -> Void) {
        starts += 1
        handler = onUpdate
    }
}

private final class Completions: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func hit() { lock.withLock { value += 1 } }
}

/// Yields until `condition` holds, with a bound so a broken signal fails instead of hanging.
@MainActor
private func waitUntil(_ condition: () -> Bool) async {
    var spins = 0
    while !condition(), spins < 20_000 {
        await Task.yield()
        spins += 1
    }
}

private struct FakeActivity: AppActivityProviding { var isActive: Bool }

@MainActor
private struct Rig {
    let file: FakeFile
    let health = FakeHealth()
    let sync = FakeSync()
    let announcer = FakeAnnouncer()
    let scheduler = FakeScheduler()
    let pending = FakePending()
    let observer = FakeObserver()
    let store: WatchGameStore

    init(state: GameState? = nil, active: Bool = true, enrolled: Bool = true) {
        var initial = GameState(now: t0, timeZone: .gmt)
        if enrolled { initial.enroll(at: t0) }
        file = FakeFile(state ?? initial)
        store = WatchGameStore(health: health, file: file, sync: sync, announcer: announcer,
                               scheduler: scheduler, activity: FakeActivity(isActive: active),
                               pending: pending, observer: observer, now: { t0 })
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WatchGameStoreTests {
    @Test func overlappingRefreshesNeverRunHealthTogether() async {
        let rig = Rig()
        async let first: Void = rig.store.refresh()
        async let second: Void = rig.store.refresh(requestAccess: true)
        async let third: Void = rig.store.refresh()
        _ = await (first, second, third)
        #expect(rig.health.maxRunning == 1)
        #expect(rig.health.calls >= 2) // the access request is never merged away
        #expect(rig.store.busy == false)
    }

    @Test func plainRequestsWaitingBehindARunJoinOneSettlement() async {
        let rig = Rig()
        rig.health.holdReads = true
        let running = Task { await rig.store.refresh() }
        await rig.health.waitForReadToStart() // the first settlement is parked inside its reading
        let second = Task { await rig.store.refresh() }
        let third = Task { await rig.store.refresh() }
        while rig.store.inFlight < 3 { await Task.yield() } // both are queued behind the parked one
        rig.health.releaseReads()
        await running.value
        await second.value
        await third.value
        #expect(rig.health.calls == 2)
    }

    @Test func hatchEventIsEmittedOnce() async throws {
        let rig = Rig()
        await rig.store.refresh()
        let event = try #require(rig.store.pendingAlert)
        #expect(event.kind == .hatched)
        #expect(rig.announcer.haptics == [event])
        await rig.store.refresh() // same reading again
        #expect(rig.announcer.haptics.count == 1)
        #expect(rig.announcer.notified.isEmpty)
    }

    @Test func failedSaveKeepsStateFileAndEvents() async {
        let rig = Rig()
        await rig.store.refresh() // load + commit not needed; settles to a hatch
        let saved = rig.store.state
        let stored = rig.file.stored
        rig.health.steps = EvolutionCard.requiredSteps(stage: 1)
        rig.file.failSave = true
        await rig.store.refresh()
        #expect(rig.store.state == saved)
        #expect(rig.file.stored == stored)
        #expect(rig.announcer.haptics.count == 1)
        #expect(rig.store.message != nil)
    }

    @Test func activeAppGetsHapticAndAlertInactiveGetsNotification() async {
        let active = Rig(active: true)
        await active.store.refresh()
        #expect(active.announcer.haptics.count == 1)
        #expect(active.store.pendingAlert != nil)
        #expect(active.announcer.notified.isEmpty)

        let inactive = Rig(active: false)
        await inactive.store.refresh()
        #expect(inactive.announcer.notified.count == 1)
        #expect(inactive.announcer.haptics.isEmpty)
        #expect(inactive.store.pendingAlert == nil)
    }

    @Test func notificationFailureStillKeepsSettlement() async {
        let rig = Rig(active: false)
        rig.announcer.failNotify = true
        await rig.store.refresh()
        #expect(rig.store.state?.monster.isEgg == false)
        #expect(rig.file.stored == rig.store.state)
    }

    @Test func migrationOnlyLoadProducesNoEvent() async throws {
        // The original built-in starter is turned into a digitama by the migration: the species really changes.
        let legacy = #"{"createdAt":821692800,"enrolledAt":821692800,"lastStepDay":821750400,"ledgers":[821750400,{"creditedDistanceMeters":0,"creditedSteps":10,"creditedXP":0},821664000,{"creditedDistanceMeters":1234.5,"creditedSteps":10,"creditedXP":0}],"monster":{"distanceMeters":1234.5,"experience":0,"id":"2540C279-A1C6-49E8-84FA-65F6F0500F83","name":"도토롱","speciesId":"starter_acorn","totalCreditedSteps":20},"observedAt":821779200,"revision":3,"timeZone":{"identifier":"GMT"},"todaySteps":10}"#
        let state = try JSONDecoder().decode(GameState.self, from: Data(legacy.utf8))
        let rig = Rig(state: state, active: true)
        rig.health.passThrough = true // the reading changes nothing, so only the migration is saved
        await rig.store.refresh()
        #expect(rig.file.saves == 1)
        #expect(rig.file.stored?.monster.speciesId == "digitama")
        #expect(rig.store.pendingAlert == nil)
        #expect(rig.announcer.haptics.isEmpty)
        #expect(rig.announcer.notified.isEmpty)
        #expect(rig.pending.stored.isEmpty)
    }

    @Test func undeliveredNotificationIsKeptForNextActivation() async {
        let rig = Rig(active: false)
        rig.announcer.failNotify = true
        await rig.store.refresh()
        #expect(rig.pending.stored.count == 1) // survives a process exit
        #expect(rig.store.pendingAlert == rig.pending.stored.first)
        #expect(rig.announcer.haptics.isEmpty)
    }

    @Test func deliveredNotificationIsNotShownAgain() async {
        let rig = Rig(active: false)
        await rig.store.refresh()
        #expect(rig.announcer.notified.count == 1)
        #expect(rig.pending.stored.isEmpty)
        #expect(rig.store.pendingAlert == nil)
    }

    @Test func storedEventAppearsOnceAfterRelaunchAndIsClearedWhenDismissed() async throws {
        let first = Rig(active: false)
        first.announcer.failNotify = true
        await first.store.refresh()
        let event = try #require(first.pending.stored.first)

        // A new process: same pending file, fresh store.
        let second = Rig(state: first.file.stored, active: true)
        second.pending.stored = first.pending.stored
        second.health.passThrough = true
        await second.store.refresh()
        #expect(second.store.pendingAlert == event)
        await second.store.refresh()
        #expect(second.store.alerts == [event])
        second.store.dismissAlert(id: event.id)
        #expect(second.store.pendingAlert == nil)
        #expect(second.pending.stored.isEmpty)
    }

    @Test func severalEventsQueueInsteadOfOverwriting() async throws {
        let rig = Rig(active: true)
        await rig.store.refresh() // hatch
        let hatch = try #require(rig.store.pendingAlert)
        rig.health.steps = EvolutionCard.requiredSteps(stage: 1)
        await rig.store.refresh() // evolution
        #expect(rig.store.alerts.count == 2)
        #expect(rig.store.alerts.first == hatch)
        rig.store.dismissAlert(id: hatch.id)
        #expect(rig.store.pendingAlert?.kind == .evolved)
        #expect(rig.pending.stored.count == 1)
    }

    @Test func notificationPermissionIsRequestedOnlyWhileActive() async {
        let active = Rig(active: true)
        active.announcer.permissionGranted = false
        await active.store.refresh()
        await active.store.permissionTask?.value
        #expect(active.store.notificationsEnabled == false)
        let inactive = Rig(active: false)
        await inactive.store.refresh()
        #expect(inactive.store.permissionTask == nil)
        #expect(inactive.store.notificationsEnabled == nil)
    }

    @Test func notificationIdentifierDiffersPerTransition() async throws {
        let rig = Rig(active: true)
        await rig.store.refresh() // hatch
        rig.health.steps = EvolutionCard.requiredSteps(stage: 1)
        await rig.store.refresh() // evolution
        let hatch = try #require(rig.store.alerts.first)
        let evolution = try #require(rig.store.alerts.last)
        #expect(hatch != evolution)
        #expect(GrowthNotifier.identifier(for: hatch) == GrowthNotifier.identifier(for: hatch))
        #expect(GrowthNotifier.identifier(for: hatch) != GrowthNotifier.identifier(for: evolution))
    }

    @Test func refreshIsScheduledAfterSettlementsButNotBeforeEnrollment() async {
        let notEnrolled = Rig(enrolled: false)
        await notEnrolled.store.refresh()
        #expect(notEnrolled.scheduler.scheduled == 0)
        await notEnrolled.store.refresh(requestAccess: true) // enrolls, then settles
        #expect(notEnrolled.scheduler.scheduled == 1)
        await notEnrolled.store.refresh()
        #expect(notEnrolled.scheduler.scheduled == 2) // one per settlement
    }

    @Test func eventIsRecordedBeforeNotificationIsSent() async {
        let rig = Rig(active: false)
        var recordedAtNotify: [GrowthEvent] = []
        rig.announcer.onNotify = { recordedAtNotify = rig.pending.stored }
        await rig.store.refresh()
        #expect(recordedAtNotify.count == 1) // write-ahead: already on disk when notify starts
        #expect(rig.pending.stored.isEmpty)   // cleared after the system accepted it
    }

    @Test func unreadablePendingFileIsNotOverwrittenAndMergesLater() async throws {
        let donor = Rig(active: false)
        donor.announcer.failNotify = true
        await donor.store.refresh()
        let old = try #require(donor.pending.stored.first)

        let rig = Rig(active: false)
        rig.pending.stored = [old]
        rig.pending.failLoad = true
        rig.announcer.failNotify = true
        await rig.store.refresh() // hatch while the file cannot be read
        #expect(rig.pending.saves == 0)
        #expect(rig.pending.stored == [old])
        #expect(rig.store.alerts.count == 1) // kept in memory

        rig.pending.failLoad = false
        rig.health.steps = EvolutionCard.requiredSteps(stage: 1)
        await rig.store.refresh() // evolution; the file is readable again
        #expect(rig.pending.stored.first == old)
        #expect(rig.pending.stored.count == 3)
        #expect(rig.store.alerts == rig.pending.stored)
    }

    @Test func observerIsStartedOnceAndOnlyWhenEnrolled() async {
        let fresh = Rig(enrolled: false)
        fresh.store.startObservingIfEnrolled()
        await fresh.store.refresh()
        #expect(fresh.observer.starts == 0)
        await fresh.store.refresh(requestAccess: true)
        await fresh.store.refresh()
        fresh.store.startObservingIfEnrolled()
        #expect(fresh.observer.starts == 1)

        let enrolled = Rig()
        enrolled.store.startObservingIfEnrolled() // launch path, before any settlement
        enrolled.store.startObservingIfEnrolled()
        #expect(enrolled.observer.starts == 1)
    }

    @Test func observerUpdateSettlesReschedulesAndCompletesOnce() async throws {
        let rig = Rig(active: false)
        rig.store.startObservingIfEnrolled()
        let handler = try #require(rig.observer.handler)
        let done = Completions()
        handler(nil) { done.hit() }
        await waitUntil { done.count > 0 }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(done.count == 1)
        #expect(rig.health.calls == 1)
        #expect(rig.scheduler.scheduled == 1)
        #expect(rig.announcer.notified.count == 1)
    }

    @Test func observerErrorCompletesOnceWithoutSettling() async throws {
        let rig = Rig()
        rig.store.startObservingIfEnrolled()
        let handler = try #require(rig.observer.handler)
        let done = Completions()
        handler(TestFailure()) { done.hit() }
        await waitUntil { done.count > 0 }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(done.count == 1)
        #expect(rig.health.calls == 0)
    }

    @Test func eventWithNotificationInFlightIsNotPresentableUntilItFails() async {
        let rig = Rig(active: false)
        var presentableDuringNotify: Int?
        rig.announcer.onNotify = { presentableDuringNotify = rig.store.presentableAlerts.count }
        await rig.store.refresh()
        #expect(presentableDuringNotify == 0) // queued, but hidden while the notification is in flight
        #expect(rig.store.alerts.isEmpty)     // delivered: removed, nothing left to show

        let failing = Rig(active: false)
        failing.announcer.failNotify = true
        await failing.store.refresh()
        #expect(failing.store.presentableAlerts.count == 1) // failed: shown at the next activation
    }

    @Test func dismissByIdRemovesOnlyThatEvent() async throws {
        let rig = Rig(active: true)
        await rig.store.refresh() // hatch
        rig.health.steps = EvolutionCard.requiredSteps(stage: 1)
        await rig.store.refresh() // evolution
        let hatch = try #require(rig.store.alerts.first)
        let evolution = try #require(rig.store.alerts.last)
        rig.store.dismissAlert(id: evolution.id) // not the head of the queue
        #expect(rig.store.alerts == [hatch])
        rig.store.dismissAlert(id: evolution.id) // already gone: no effect
        #expect(rig.store.alerts == [hatch])
        #expect(rig.pending.stored == [hatch])
    }

    @Test func dismissedEventDoesNotReturnWhenUnreadableFileIsMerged() async throws {
        let donor = Rig(active: false)
        donor.announcer.failNotify = true
        await donor.store.refresh()
        let old = try #require(donor.pending.stored.first)

        let rig = Rig(active: true)
        rig.pending.stored = [old]
        rig.pending.failLoad = true
        await rig.store.refresh() // hatch queued in memory only
        let hatch = try #require(rig.store.alerts.first)
        rig.store.dismissAlert(id: hatch.id)
        rig.pending.failLoad = false
        await rig.store.refresh()
        #expect(rig.store.alerts == [old])
        #expect(rig.pending.stored == [old])
    }

    @Test func failedPendingWriteIsRetriedAtNextSettlement() async {
        let rig = Rig(active: true)
        rig.pending.failSave = true
        await rig.store.refresh() // hatch; the queue cannot be written
        #expect(rig.pending.stored.isEmpty)
        rig.pending.failSave = false
        rig.health.passThrough = true
        await rig.store.refresh() // nothing new, but the queue is saved now
        #expect(rig.pending.stored == rig.store.alerts)
        #expect(rig.pending.stored.count == 1)
    }

    @Test func mergeAfterUnreadablePendingFileIsSaved() async throws {
        let donor = Rig(active: false)
        donor.announcer.failNotify = true
        await donor.store.refresh()
        let old = try #require(donor.pending.stored.first)

        let rig = Rig(active: true)
        rig.pending.stored = [old]
        rig.pending.failLoad = true
        await rig.store.refresh()
        rig.pending.failLoad = false
        rig.health.passThrough = true
        await rig.store.refresh() // no new event: the merge itself must be written
        #expect(rig.pending.stored == rig.store.alerts)
        #expect(rig.pending.stored.count == 2)
    }

    @Test func coldLoadFailureKeepsRefreshChainAndFile() async {
        let rig = Rig()
        rig.file.failLoad = true
        let stored = rig.file.stored
        await rig.store.refresh()
        #expect(rig.store.state == nil)
        #expect(rig.scheduler.scheduled == 1) // enrollment unknown, still rescheduled
        #expect(rig.file.stored == stored)
        #expect(rig.file.saves == 0)
        rig.file.failLoad = false
        await rig.store.refresh() // retried
        #expect(rig.store.state != nil)
    }

    @Test func backgroundDeliveryIsRetriedEachSettlementWhileEnrolled() async {
        let rig = Rig()
        await rig.store.refresh()
        await rig.store.refresh()
        #expect(rig.observer.starts == 1)
        #expect(rig.observer.deliveryRetries == 2)
        let fresh = Rig(enrolled: false)
        await fresh.store.refresh()
        #expect(fresh.observer.deliveryRetries == 0)
    }
}

@MainActor
struct SnapshotSendPolicyTests {
    private let base = GameState(now: t0, timeZone: .gmt).snapshot

    private func snapshot(revision: Int, of origin: MonsterSnapshot? = nil) -> MonsterSnapshot {
        let source = origin ?? base
        return MonsterSnapshot(schemaVersion: source.schemaVersion, revision: revision, createdAt: source.createdAt,
                               monster: source.monster, todaySteps: nil, observedAt: nil, timeZone: nil, dex: source.dex)
    }

    private func context(_ snapshot: MonsterSnapshot) -> [String: Any] {
        [SnapshotSendPolicy.contextKey: try! JSONEncoder().encode(snapshot)]
    }

    @Test func sameRevisionIsSkipped() {
        let sent = snapshot(revision: 4)
        #expect(!SnapshotSendPolicy.shouldSend(sent, lastSubmitted: context(sent)))
    }

    @Test func forceSendsEvenWithSameRevision() {
        let sent = snapshot(revision: 4)
        #expect(SnapshotSendPolicy.shouldSend(sent, lastSubmitted: context(sent), force: true))
    }

    @Test func newerRevisionIsSent() {
        #expect(SnapshotSendPolicy.shouldSend(snapshot(revision: 5), lastSubmitted: context(snapshot(revision: 4))))
    }

    @Test func differentPartnerIsSentEvenWithSameRevision() {
        let other = snapshot(revision: 4, of: GameState(now: t0, timeZone: .gmt).snapshot)
        #expect(SnapshotSendPolicy.shouldSend(other, lastSubmitted: context(snapshot(revision: 4))))
    }

    @Test func missingOrUndecodableContextIsSent() {
        let current = snapshot(revision: 4)
        #expect(SnapshotSendPolicy.shouldSend(current, lastSubmitted: [:]))
        #expect(SnapshotSendPolicy.shouldSend(current, lastSubmitted: [SnapshotSendPolicy.contextKey: Data("x".utf8)]))
        #expect(SnapshotSendPolicy.shouldSend(current, lastSubmitted: [SnapshotSendPolicy.contextKey: "not data"]))
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct BackgroundRunTests {
    private final class Counter { var completed = 0 }

    /// Waits well under the 5 s watchdog, so a pass means the work end completed it and not the timeout.
    private func completedBeforeWatchdog(_ counter: Counter) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while counter.completed == 0 {
            if Task.isCancelled || ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    @Test func completesOnceWhenWorkFinishes() async {
        let counter = Counter()
        BackgroundRun.run(timeout: .seconds(5), work: { }, complete: { counter.completed += 1 })
        #expect(await completedBeforeWatchdog(counter))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(counter.completed == 1)
    }

    @Test func completesOnceWhenWorkThrows() async {
        let counter = Counter()
        BackgroundRun.run(timeout: .seconds(5), work: { throw TestFailure() }, complete: { counter.completed += 1 })
        #expect(await completedBeforeWatchdog(counter))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(counter.completed == 1)
    }

    @Test func completesOnceOnTimeoutEvenIfWorkFinishesLater() async {
        let counter = Counter()
        var finish: CheckedContinuation<Void, Never>?
        BackgroundRun.run(timeout: .milliseconds(20), work: {
            await withCheckedContinuation { finish = $0 }
        }, complete: { counter.completed += 1 })
        while counter.completed == 0 { await Task.yield() } // the timeout fired
        while finish == nil { await Task.yield() }
        finish?.resume()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(counter.completed == 1)
    }

    @Test func earlyFinishAndLaterCompletionStillCountOnce() async {
        let counter = Counter()
        var finish: CheckedContinuation<Void, Never>?
        let early = BackgroundRun.run(timeout: .seconds(5), work: {
            await withCheckedContinuation { finish = $0 }
        }, complete: { counter.completed += 1 })
        early() // e.g. the expiration handler
        early()
        while finish == nil { await Task.yield() }
        finish?.resume()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(counter.completed == 1)
    }
}
