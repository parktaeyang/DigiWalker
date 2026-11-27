import DigiWalkerCore
import Foundation
import WatchConnectivity

enum SnapshotSendPolicy {
    static let contextKey = "monster_snapshot"

    /// False only when the last submitted context decodes to a snapshot of the same partner, revision and an equal or newer schema.
    /// A missing or undecodable context means send.
    /// `force` is for recovery events (iPhone app reinstalled, reachable again) where the iPhone may have lost its cache.
    static func shouldSend(_ snapshot: MonsterSnapshot, lastSubmitted context: [String: Any], force: Bool = false) -> Bool {
        if force { return true }
        guard let data = context[contextKey] as? Data,
              let last = try? JSONDecoder().decode(MonsterSnapshot.self, from: data) else { return true }
        if last.monster.id != snapshot.monster.id { return true }
        // Same partner and revision: only a newer schema (v2 -> v3 after a watch update) is worth sending again.
        return last.revision != snapshot.revision || snapshot.schemaVersion > last.schemaVersion
    }
}

/// Reads a "new egg" request out of a `transferUserInfo` dictionary. Pure, so it can be tested without a session.
nonisolated enum NewEggRequestPayload {
    /// Nil for a missing key, a value that is not JSON `Data`, or data that is not a request (damaged or unknown).
    static func decode(_ userInfo: [String: Any]) -> NewEggRequest? {
        guard let data = userInfo[NewEggRequest.userInfoKey] as? Data else { return nil }
        return try? JSONDecoder().decode(NewEggRequest.self, from: data)
    }
}

/// Requests received but not yet handled, counted from the delegate callback itself (before hopping to the main
/// actor), so a background task can tell "nothing arrived" from "arrived and still running".
nonisolated final class RequestsInFlight: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func begin() { lock.withLock { value += 1 } }
    func end() { lock.withLock { value -= 1 } }
}

/// Whether the session has reported the end of an activation attempt (success or failure), set from the delegate callback.
nonisolated final class ActivationReport: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var reported: Bool { lock.withLock { value } }
    func set(_ reported: Bool) { lock.withLock { value = reported } }
}

/// When a connectivity background task may finish. Pure, so it can be tested without a session.
nonisolated enum ConnectivityIdle {
    /// Not idle until activation has finished: before that `hasContentPending` is not yet meaningful and a transfer
    /// that woke the app has not been delivered. A failed activation (reported with an error) or an unsupported
    /// session must not wait forever.
    static func isIdle(
        supported: Bool,
        activated: Bool,
        activationReported: Bool,
        hasContentPending: Bool,
        requestsInFlight: Int
    ) -> Bool {
        if requestsInFlight > 0 { return false }
        guard supported else { return true }
        if !activated { return activationReported }
        return !hasContentPending
    }
}

@MainActor
final class WatchSyncService: NSObject, WCSessionDelegate {
    private var latest: MonsterSnapshot?
    private var session: WCSession? { WCSession.isSupported() ? .default : nil }
    /// Applies a request from the iPhone. Set once at launch; requests that arrive earlier wait in `buffered`.
    var onNewEggRequest: (@MainActor (NewEggRequest) async -> Void)? {
        didSet { drainBuffered() }
    }
    private var buffered: [NewEggRequest] = []
    nonisolated let inFlight = RequestsInFlight()
    nonisolated let activation = ActivationReport()

    /// Activates the session at launch, so a request transferred while the app was not running is delivered.
    func activate() {
        guard let session else { return }
        session.delegate = self
        if session.activationState != .activated {
            activation.set(false)
            session.activate()
        }
    }

    /// True until the session is activated (or activation failed), while the system still holds content for this
    /// app, or while a received request is being handled.
    var isBusy: Bool {
        !ConnectivityIdle.isIdle(
            supported: session != nil,
            activated: session?.activationState == .activated,
            activationReported: activation.reported,
            hasContentPending: session?.hasContentPending ?? false,
            requestsInFlight: inFlight.count
        )
    }

    func publish(_ snapshot: MonsterSnapshot) {
        latest = snapshot
        guard let session else { return }
        if session.activationState == .activated {
            flush()
        } else {
            session.delegate = self
            session.activate()
        }
    }

    func republish(_ snapshot: MonsterSnapshot) {
        latest = snapshot
        guard let session else { return }
        if session.activationState == .activated {
            flush(force: true)
        } else {
            session.delegate = self
            session.activate()
        }
    }

    private func receive(_ request: NewEggRequest) {
        guard let handler = onNewEggRequest else {
            buffered.append(request) // still counted as in flight until a handler applies it
            return
        }
        Task {
            await handler(request)
            inFlight.end()
        }
    }

    private func drainBuffered() {
        guard let handler = onNewEggRequest, !buffered.isEmpty else { return }
        let waiting = buffered
        buffered = []
        for request in waiting {
            Task {
                await handler(request)
                inFlight.end()
            }
        }
    }

    /// `force` skips the same-revision shortcut. A reinstalled or cache-cleared iPhone app needs the snapshot again
    /// even though the last submitted context on the watch is unchanged.
    private func flush(force: Bool = false) {
        guard let latest, let session, session.activationState == .activated else { return }
        // applicationContext holds the last context whose submission succeeded, so a failed send is retried.
        guard SnapshotSendPolicy.shouldSend(latest, lastSubmitted: session.applicationContext, force: force) else { return }
        do {
            let data = try JSONEncoder().encode(latest)
            try session.updateApplicationContext([SnapshotSendPolicy.contextKey: data])
        } catch {
            // Keep the durable state as the retry source on activation, foreground or reachability change.
            NSLog("DigiWalker: snapshot delivery deferred (%@)", error.localizedDescription)
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        activation.set(true)
        Task { @MainActor in self.flush() }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let request = NewEggRequestPayload.decode(userInfo) else {
            NSLog("DigiWalker: ignored an unreadable userInfo transfer")
            return
        }
        inFlight.begin()
        Task { @MainActor in self.receive(request) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.flush(force: reachable) }
    }

    nonisolated func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        let installed = session.isCompanionAppInstalled
        Task { @MainActor in self.flush(force: installed) }
    }
}
