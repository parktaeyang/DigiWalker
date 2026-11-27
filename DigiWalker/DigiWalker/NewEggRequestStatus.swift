import DigiWalkerCore
import Foundation

/// An iPhone request the watch has not answered yet, saved before it is sent so a relaunch still shows it.
struct PendingNewEgg: Codable, Equatable {
    enum Phase: String, Codable {
        /// Saved but not yet handed to the system queue. Only seen after a relaunch that interrupted the hand-over;
        /// the same request is then sent again (the watch ignores a repeated target).
        case preparing
        /// Handed to the system queue; goes out when the watch is reachable.
        case queued
        /// The system reports the transfer finished; the watch has not published a new partner yet.
        case delivered
        /// The system reported an error for the transfer. The user can cancel and ask again.
        case failed
    }

    let request: NewEggRequest
    var phase: Phase

    /// What to do with a saved request after the session activates, given whether its transfer is still queued.
    enum Reconciliation: Equatable { case none, markQueued, resend, markDelivered }

    func reconciliation(stillQueued: Bool) -> Reconciliation {
        switch (phase, stillQueued) {
        case (.preparing, true): .markQueued
        case (.preparing, false): .resend
        case (.queued, false): .markDelivered
        default: .none
        }
    }

    enum CancelResult: Equatable {
        /// The transfer was stopped before leaving (or the request was already past that point): forget it.
        case cleared
        /// The transfer could not be found, so it may already be on its way: keep the note, as "delivered".
        case keptAsDelivered
    }

    /// Only a transfer that was really found and cancelled counts as stopped. Later phases just clear the note.
    mutating func resolveCancel(transferCancelled: Bool) -> CancelResult {
        switch phase {
        case .preparing, .queued:
            if transferCancelled { return .cleared }
            phase = .delivered
            return .keptAsDelivered
        case .delivered, .failed:
            return .cleared
        }
    }

    /// A snapshot of another partner means the new egg started (or the watch was reset): the request is done.
    func isResolved(by snapshot: MonsterSnapshot) -> Bool {
        snapshot.monster.id != request.targetMonsterId
    }

    /// Applies the system's transfer result. A failure report may still follow a "finished" one for the same request
    /// (queued -> delivered -> failed); nothing else changes a phase. Returns whether the phase changed.
    mutating func applyTransferResult(failed: Bool) -> Bool {
        switch (phase, failed) {
        case (.preparing, _), (.queued, _): phase = failed ? .failed : .delivered
        case (.delivered, true): phase = .failed
        default: return false
        }
        return true
    }
}

/// What the main screen shows for the "new egg" feature. Pure, so it can be tested without a session.
enum NewEggRequestStatus: Equatable {
    /// No cache, a partner that is not finished, or no new egg possible: show nothing.
    case hidden
    /// The partner is finished but the cache is older than v4: the watch app cannot take requests yet.
    case needsWatchUpdate
    case available
    case queued
    case delivered
    case failed
    /// A request could be made, but the watch is not activated, paired or installed: nothing is sent or saved.
    case notConnected

    static func evaluate(snapshot: MonsterSnapshot?, pending: PendingNewEgg?, watchLinked: Bool = true) -> NewEggRequestStatus {
        guard let snapshot, snapshot.monster.canStartNewEgg else { return .hidden }
        if let pending, !pending.isResolved(by: snapshot) {
            switch pending.phase {
            case .preparing, .queued: return .queued
            case .delivered: return .delivered
            case .failed: return .failed
            }
        }
        guard snapshot.schemaVersion >= MonsterSnapshot.currentSchemaVersion else { return .needsWatchUpdate }
        return watchLinked ? .available : .notConnected
    }
}
