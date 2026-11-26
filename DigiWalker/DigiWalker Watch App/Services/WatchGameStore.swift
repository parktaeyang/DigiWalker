import Combine
import DigiWalkerCore
import Foundation

@MainActor
final class WatchGameStore: ObservableObject {
    @Published private(set) var state: GameState?
    @Published private(set) var message: String?
    @Published private(set) var busy = false
    /// Hatches and evolutions waiting for the foreground alert, oldest first. Persisted until dismissed,
    /// so an event that could not be delivered as a notification survives the app being killed.
    @Published private(set) var alerts: [GrowthEvent] = []
    /// Nil until the permission state is known.
    @Published private(set) var notificationsEnabled: Bool?
    /// Ids of events whose notification is being handed to the system. They are not shown as alerts: if the
    /// notification succeeds they are gone, if it fails they become presentable.
    @Published private(set) var notifying: Set<String> = []
    /// Events the foreground alert may show: those decided for the foreground or whose notification failed.
    var presentableAlerts: [GrowthEvent] { alerts.filter { !notifying.contains($0.id) } }
    var pendingAlert: GrowthEvent? { presentableAlerts.first }
    private let file: any StateStoring
    private let health: any HealthReading
    private let sync: any SnapshotPublishing
    private let announcer: any GrowthAnnouncing
    private let scheduler: any RefreshScheduling
    private let activity: any AppActivityProviding
    private let pending: any PendingEventStoring
    private let observer: any HealthObserving
    private let widget: any WidgetPublishing
    private let wakeFile: any BackgroundLogging
    private let now: () -> Date
    /// Background wake-ups for the diagnostic line: the newest 20, plus per-day counts and the last time.
    @Published private(set) var wakeData = BackgroundLogData()
    /// True once the log file was read successfully. Until then it is never overwritten (same as the pending file).
    private var wakeLogLoaded = false
    /// The in-memory log differs from the file (merged after a failed read, or a failed write); saved on the next chance.
    private var wakeLogDirty = false
    /// Requests inside refresh(), including ones that joined a queued settlement; internal so tests can tell when others are queued.
    private(set) var inFlight = 0
    /// True once the pending file was read successfully. Until then it is never overwritten.
    private var pendingLoaded = false
    /// The in-memory queue differs from the pending file (unsaved change or failed write); saved on the next chance.
    private var pendingDirty = false
    /// Dismissed while the pending file was unreadable, so merging the file later does not bring them back.
    private var dismissedWhileUnloaded: Set<String> = []
    private var observing = false
    /// Notification permission request, kept outside the settlement chain because it waits for the user.
    private(set) var permissionTask: Task<Void, Never>?
    /// Last queued settlement; the next one starts after it finishes.
    private var tail: Task<SettlementOutcome, Never>?
    /// Queued plain settlement that has not started yet; later plain requests join it and share its outcome.
    private var waitingPlain: Task<SettlementOutcome, Never>?

    init(
        health: any HealthReading = HealthService(),
        file: any StateStoring = StateFile<GameState>(url: URL.applicationSupportDirectory.appending(path: "game-state.json")),
        sync: any SnapshotPublishing = WatchSyncService(),
        announcer: any GrowthAnnouncing = GrowthNotifier(),
        scheduler: any RefreshScheduling = NoRefreshScheduler(),
        activity: any AppActivityProviding = WatchAppActivity(),
        pending: any PendingEventStoring = PendingEventFile(),
        observer: any HealthObserving = HealthObserver(),
        widget: any WidgetPublishing = WidgetPublisher(),
        wakeLog: any BackgroundLogging = BackgroundLogFile(),
        now: @escaping () -> Date = { .now }
    ) {
        self.health = health
        self.file = file
        self.sync = sync
        self.announcer = announcer
        self.scheduler = scheduler
        self.activity = activity
        self.pending = pending
        self.observer = observer
        self.widget = widget
        self.wakeFile = wakeLog
        self.now = now
    }

    /// Settlements run one at a time. A request made while another runs waits for it instead of being dropped.
    /// Plain requests made before a queued plain one starts share its result.
    /// `wake` names a background wake-up for the diagnostic log. Its arrival is recorded right away, before waiting
    /// in the chain, and the result is added afterwards; neither step is part of the serialized chain. A wake that
    /// arrives while the app is active is not a background run and is not recorded.
    func refresh(requestAccess: Bool = false, wake: WakeSource? = nil) async {
        let wakeId = wake.flatMap { beginWake($0) }
        let outcome = await runSettlement(requestAccess: requestAccess)
        if let wakeId { finishWake(wakeId, outcome: outcome) }
    }

    private func runSettlement(requestAccess: Bool) async -> SettlementOutcome {
        inFlight += 1
        busy = true
        defer {
            inFlight -= 1
            busy = inFlight > 0
        }
        if !requestAccess, let waiting = waitingPlain {
            return await waiting.value
        }
        let previous = tail
        let task = Task { [self] in
            _ = await previous?.value
            if !requestAccess { waitingPlain = nil }
            return await settle(requestAccess: requestAccess)
        }
        tail = task
        if !requestAccess { waitingPlain = task }
        return await task.value
    }

    private func settle(requestAccess: Bool) async -> SettlementOutcome {
        var outcome = SettlementOutcome.unchanged
        let loadingSaved = state == nil
        // One refresh request per settlement, made before the slow work so the chain survives a stopped process.
        var scheduled = false
        func ensureScheduled() {
            guard !scheduled, state?.enrolledAt != nil else { return }
            scheduled = true
            scheduler.scheduleNextRefresh()
        }
        syncPendingEvents()
        do {
            if state == nil {
                if let saved = try file.load() {
                    var updated = saved
                    updated.migrateLegacyStarter()
                    // Random evolution results only become real once commit() saves them.
                    updated.migrateToEvolutionCatalog()
                    if updated == saved {
                        state = saved
                    } else {
                        try commit(updated)
                    }
                } else {
                    try commit(GameState())
                }
            }
            guard var saved = state else { return outcome }
            ensureScheduled()
            sync.publish(saved.snapshot)
            // The copy is refreshed after a commit; the first load only fills in a missing or stale one.
            if loadingSaved { publishWidget(saved) }
            if requestAccess {
                try await health.requestAccess()
                if saved.enrolledAt == nil {
                    saved.enroll(at: now())
                    try commit(saved)
                }
            }
            guard saved.enrolledAt != nil else {
                outcome = .notEnrolled
                return outcome
            }
            ensureScheduled()
            startObservingIfEnrolled()
            observer.retryBackgroundDelivery()
            let candidate = try await health.reconciled(saved, through: now())
            if candidate != saved {
                try commit(candidate)
                // Write-ahead: the event is recorded synchronously right after the commit, before anything can
                // suspend, so a stop during delivery cannot lose it. Only a committed settlement makes events.
                let event = GrowthEvent.between(saved, candidate)
                let foreground = activity.isActive
                if let event {
                    // Hidden from the alert from the moment it is queued, so an activation while the
                    // notification is in flight cannot show it twice.
                    if !foreground { notifying.insert(event.id) }
                    enqueueAlert(event)
                }
                outcome = event == nil ? .settled : .growth
                sync.publish(candidate.snapshot)
                publishWidget(candidate)
                if let event { await deliver(event, foreground: foreground) }
            } else {
                // Nothing new to commit, but a step change held back earlier may be due for a reload; the
                // publisher compares with its own reload record and skips when there is nothing to do.
                publishWidget(saved)
            }
            message = candidate.todaySteps == nil ? "읽을 수 있는 오늘 걸음 기록이 없어요. 건강 권한을 확인해 주세요." : nil
        } catch {
            outcome = .failed
            // A failed first load or migration save keeps the old file; the next refresh retries it.
            // Whether the partner is enrolled is unknown then, so keep the refresh chain alive anyway.
            if state == nil, !scheduled {
                scheduled = true
                scheduler.scheduleNextRefresh()
            }
            message = loadingSaved && state == nil
                ? "저장된 기록을 불러오거나 이전하지 못했어요. 앱을 다시 열면 다시 시도해요. (\(error.localizedDescription))"
                : error.localizedDescription
        }
        // Ask once the partner is connected, only while the user can see the prompt.
        if activity.isActive, state?.enrolledAt != nil, permissionTask == nil {
            permissionTask = Task { [self] in
                notificationsEnabled = await announcer.requestPermission()
                permissionTask = nil
            }
        }
        return outcome
    }

    /// Starts the HealthKit observer once the partner is enrolled (enrollment follows the access request).
    /// Called at launch too, because a background delivery relaunch expects the observer to be registered.
    func startObservingIfEnrolled() {
        guard !observing else { return }
        let enrolled = state?.enrolledAt != nil || ((try? file.load()) ?? nil)?.enrolledAt != nil
        guard enrolled else { return }
        observing = true
        observer.start { [weak self] error, complete in
            Task { @MainActor in
                guard let self else { complete(); return }
                self.handleObserverUpdate(error: error, complete: complete)
            }
        }
    }

    /// Settles for an observer wake-up and calls `complete` exactly once on every path. Whether the app was
    /// active is decided here, on arrival, before any waiting: a callback while the app is open is not logged.
    func handleObserverUpdate(error: Error?, complete: @escaping () -> Void) {
        let wakeId = beginWake(.healthKit)
        if let error {
            NSLog("DigiWalker: health observer failed (%@)", error.localizedDescription)
            if let wakeId { finishWake(wakeId, outcome: .failed) }
            complete()
            return
        }
        BackgroundRun.run(work: { [self] in
            let outcome = await runSettlement(requestAccess: false)
            if let wakeId { finishWake(wakeId, outcome: outcome) }
        }, complete: complete)
    }

    /// Display copy for the complication. Never throws, so it cannot affect settlement or notifications.
    private func publishWidget(_ state: GameState) {
        widget.publish(WidgetSnapshot(state: state, now: now()), foreground: activity.isActive)
    }

    /// Reads the log file once. If it cannot be read, nothing is written over it and the next call retries;
    /// runs recorded meanwhile stay in memory and are merged in when the file is read.
    private func loadWakeLogOnce() {
        guard !wakeLogLoaded else { return }
        do {
            let stored = try wakeFile.load()
            let merged = stored.merging(unsaved: wakeData)
            if merged != stored { wakeLogDirty = true }
            wakeData = merged
            wakeLogLoaded = true
        } catch {
            NSLog("DigiWalker: background log unreadable (%@)", error.localizedDescription)
        }
    }

    private func saveWakeLog() {
        guard wakeLogLoaded else { return }
        do {
            try wakeFile.save(wakeData)
            wakeLogDirty = false
        } catch {
            wakeLogDirty = true
            NSLog("DigiWalker: background log not saved (%@)", error.localizedDescription)
        }
    }

    /// Records that a background wake-up arrived. Returns nil (nothing recorded) if the app is active.
    private func beginWake(_ source: WakeSource) -> UUID? {
        guard !activity.isActive else { return nil }
        loadWakeLogOnce()
        let entry = BackgroundLogEntry(at: now(), source: source)
        wakeData = wakeData.arriving(entry)
        saveWakeLog()
        return entry.id
    }

    private func finishWake(_ id: UUID, outcome: SettlementOutcome) {
        loadWakeLogOnce()
        wakeData = wakeData.finishing(id: id, outcome: outcome)
        saveWakeLog()
    }

    /// Shows the saved log on the home screen; retried on each call until the file could be read.
    func loadWakeLog() {
        loadWakeLogOnce()
        if wakeLogDirty { saveWakeLog() }
    }

    /// Removes the event the alert showed. Matching by id keeps a queue change from deleting another event.
    func dismissAlert(id: String) {
        removeAlert(id: id)
    }

    private func removeAlert(id: String) {
        if !pendingLoaded { dismissedWhileUnloaded.insert(id) }
        guard alerts.contains(where: { $0.id == id }) else { return }
        alerts.removeAll { $0.id == id }
        persistAlerts()
    }

    /// Reads the pending file once, then writes the queue if it holds changes the file lacks.
    private func syncPendingEvents() {
        loadPendingEventsOnce()
        if pendingLoaded, pendingDirty { writePendingEvents() }
    }

    private func loadPendingEventsOnce() {
        guard !pendingLoaded else { return }
        do {
            let stored = try pending.load().filter { !dismissedWhileUnloaded.contains($0.id) }
            pendingLoaded = true
            let merged = stored + alerts.filter { event in !stored.contains(event) }
            // Anything the file lacked (or that was dismissed meanwhile) still has to be written.
            if merged != stored || !dismissedWhileUnloaded.isEmpty { pendingDirty = true }
            dismissedWhileUnloaded = []
            alerts = merged
        } catch {
            // Stay unloaded: nothing is written over the unreadable file, and the next call retries.
            NSLog("DigiWalker: pending growth events unreadable (%@)", error.localizedDescription)
        }
    }

    private func enqueueAlert(_ event: GrowthEvent) {
        guard !alerts.contains(event) else { return }
        alerts.append(event)
        persistAlerts()
    }

    private func persistAlerts() {
        pendingDirty = true
        syncPendingEvents()
    }

    private func writePendingEvents() {
        do {
            try pending.save(alerts)
            pendingDirty = false
        } catch {
            // Stays dirty: the next settlement writes the queue again.
            NSLog("DigiWalker: pending growth events not saved (%@)", error.localizedDescription)
        }
    }

    /// The event is already queued (write-ahead). In the foreground it stays as an alert; in the background
    /// it is dropped once the system accepted the notification, and kept for the next activation otherwise.
    private func deliver(_ event: GrowthEvent, foreground: Bool) async {
        if foreground {
            announcer.playHaptic(for: event)
            return
        }
        do {
            try await announcer.notify(event)
            removeAlert(id: event.id)
        } catch {
            NSLog("DigiWalker: growth notification failed (%@)", error.localizedDescription)
        }
        notifying.remove(event.id) // a failed one is now presentable
    }

    private func commit(_ candidate: GameState) throws {
        try file.save(candidate)
        state = candidate
    }
}
