import DigiWalkerCore
import Foundation
import WatchConnectivity

enum SnapshotSendPolicy {
    static let contextKey = "monster_snapshot"

    /// False only when the last submitted context decodes to a snapshot of the same partner and revision.
    /// A missing or undecodable context means send.
    /// `force` is for recovery events (iPhone app reinstalled, reachable again) where the iPhone may have lost its cache.
    static func shouldSend(_ snapshot: MonsterSnapshot, lastSubmitted context: [String: Any], force: Bool = false) -> Bool {
        if force { return true }
        guard let data = context[contextKey] as? Data,
              let last = try? JSONDecoder().decode(MonsterSnapshot.self, from: data) else { return true }
        return last.monster.id != snapshot.monster.id || last.revision != snapshot.revision
    }
}

@MainActor
final class WatchSyncService: NSObject, WCSessionDelegate {
    private var latest: MonsterSnapshot?
    private var session: WCSession? { WCSession.isSupported() ? .default : nil }

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
        Task { @MainActor in self.flush() }
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
