import DigiWalkerCore
import Foundation
import WatchConnectivity

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

    private func flush() {
        guard let latest, let session, session.activationState == .activated else { return }
        do {
            let data = try JSONEncoder().encode(latest)
            try session.updateApplicationContext(["monster_snapshot": data])
        } catch {
            // Keep the durable state as the retry source on activation, foreground or reachability change.
            NSLog("DigiWalker: snapshot delivery deferred (%@)", error.localizedDescription)
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.flush() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.flush() }
    }

    nonisolated func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        Task { @MainActor in self.flush() }
    }
}
