import Combine
import DigiWalkerCore
import Foundation
import WatchConnectivity

struct PhoneCache: Codable {
    let snapshot: MonsterSnapshot
    let receivedAt: Date
}

@MainActor
final class PhoneSyncService: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var cache: PhoneCache?
    @Published private(set) var status = "워치 연결 확인 중"
    private let file = StateFile<PhoneCache>(url: URL.applicationSupportDirectory.appending(path: "watch-cache.json"))

    override init() {
        super.init()
        do { cache = Self.validated(try file.load()) } catch { status = "저장된 워치 기록을 읽을 수 없어요." }
        guard WCSession.isSupported() else {
            status = "이 기기에서는 워치 연결을 지원하지 않아요."
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// A restored cache is only used if it passes the same checks as a freshly received snapshot.
    /// An invalid one is ignored (the file stays on disk) until the next valid snapshot replaces it.
    static func validated(_ cache: PhoneCache?) -> PhoneCache? {
        guard let cache, cache.snapshot.supersedes(nil) else { return nil }
        return cache
    }

    private func updateStatus() {
        let session = WCSession.default
        guard session.activationState == .activated else {
            status = "워치 연결 대기 중"
            return
        }
        if !session.isPaired { status = "페어링된 워치가 없어요." }
        else if !session.isWatchAppInstalled { status = "워치에 DigiWalker를 설치해 주세요." }
        else { status = session.isReachable ? "워치 앱 연결됨" : "워치 오프라인 · 마지막 수신 기록" }
    }

    private func receive(_ data: Data?) {
        guard let data else { return }
        do {
            let snapshot = try JSONDecoder().decode(MonsterSnapshot.self, from: data)
            guard snapshot.supersedes(cache?.snapshot) else { return }
            let updated = PhoneCache(snapshot: snapshot, receivedAt: .now)
            try file.save(updated)
            cache = updated
        } catch { status = "워치 기록을 읽거나 저장하지 못했어요." }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let data = session.receivedApplicationContext["monster_snapshot"] as? Data
        Task { @MainActor in
            self.updateStatus()
            self.receive(data)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        let data = context["monster_snapshot"] as? Data
        Task { @MainActor in self.receive(data) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.updateStatus() }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.updateStatus() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in self.updateStatus() }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
