import Combine
import DigiWalkerCore
import Foundation
import UIKit
import WatchConnectivity

struct PhoneCache: Codable {
    let snapshot: MonsterSnapshot
    let receivedAt: Date
}

@MainActor
final class PhoneSyncService: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var cache: PhoneCache?
    @Published private(set) var status = "워치 연결 확인 중"
    @Published private(set) var pendingNewEgg: PendingNewEgg?
    private let file = StateFile<PhoneCache>(url: URL.applicationSupportDirectory.appending(path: "watch-cache.json"))
    private let pendingFile = StateFile<PendingNewEgg>(url: URL.applicationSupportDirectory.appending(path: "pending-new-egg.json"))

    private let widget: PhoneWidgetPublishing

    /// Activated, paired and with the watch app installed: the only state in which a request may be saved and sent.
    @Published private(set) var watchLinked = false

    var newEggStatus: NewEggRequestStatus {
        .evaluate(snapshot: cache?.snapshot, pending: pendingNewEgg, watchLinked: watchLinked)
    }

    private static func isLinked(_ session: WCSession) -> Bool {
        session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
    }

    init(widget: PhoneWidgetPublishing = PhoneWidgetPublisher()) {
        self.widget = widget
        super.init()
        do { cache = Self.validated(try file.load()) } catch { status = "저장된 워치 기록을 읽을 수 없어요." }
        pendingNewEgg = try? pendingFile.load()
        resolvePending()
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
        watchLinked = Self.isLinked(session)
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
            publishWidget()
            resolvePending()
        } catch { status = "워치 기록을 읽거나 저장하지 못했어요." }
    }

    private func publishWidget() {
        guard let cache else { return }
        widget.publish(cache, foreground: UIApplication.shared.applicationState == .active)
    }

    /// Called when the app becomes active: fills in the widget copy of an already cached snapshot (e.g. after an
    /// app update), and refreshes the receive time shown on it. Does nothing without a valid cache.
    func refreshWidget() { publishWidget() }

    /// Drops a saved request once the cache shows another partner than the one it targeted.
    private func resolvePending() {
        guard let pending = pendingNewEgg, let snapshot = cache?.snapshot, pending.isResolved(by: snapshot) else { return }
        clearPending()
    }

    private func clearPending() {
        if Self.discard(pendingFile.url) {
            pendingNewEgg = nil
        } else {
            status = "새 알 요청 기록을 지우지 못했어요. 잠시 뒤 다시 시도해 주세요."
        }
    }

    /// Removes the saved request. If the file cannot be removed it is overwritten with `null`, which no longer decodes
    /// as a request, so a relaunch cannot bring a cleared request back. False only if neither works.
    nonisolated static func discard(_ url: URL) -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return true
        } catch {
            return (try? Data("null".utf8).write(to: url, options: .atomic)) != nil
        }
    }

    /// Asks the watch to start a new egg for the partner it was shown for. The request is saved as `.preparing`,
    /// handed to `transferUserInfo` (so it still arrives if the watch is out of reach), then marked `.queued`.
    /// Does nothing unless the status is `.available` and the cache still holds `target`, so a partner changed
    /// since the user opened the dialog is never requested.
    func requestNewEgg(target: UUID) {
        guard WCSession.isSupported() else { return }
        watchLinked = Self.isLinked(WCSession.default)
        guard newEggStatus == .available, let snapshot = cache?.snapshot, snapshot.monster.id == target else { return }
        let request = NewEggRequest(targetMonsterId: target, requestedAt: .now)
        var pending = PendingNewEgg(request: request, phase: .preparing)
        do {
            try pendingFile.save(pending)
            let data = try JSONEncoder().encode(request)
            pendingNewEgg = pending
            WCSession.default.transferUserInfo([NewEggRequest.userInfoKey: data])
            pending.phase = .queued
            pendingNewEgg = pending
            // If this write fails the file still says `.preparing`; a relaunch then finds the transfer queued.
            try? pendingFile.save(pending)
        } catch {
            _ = Self.discard(pendingFile.url)
            pendingNewEgg = nil
            status = "새 알 요청을 보내지 못했어요."
        }
    }

    /// Stops a still-queued transfer and forgets the request, but only if that transfer was found and cancelled.
    /// Otherwise it may already have left: the note stays as "delivered" and only the iPhone's note can be cleared.
    func cancelNewEggRequest() {
        guard var pending = pendingNewEgg else { return }
        var cancelled = false
        if WCSession.isSupported(), WCSession.default.activationState == .activated {
            for transfer in WCSession.default.outstandingUserInfoTransfers
            where Self.requestId(of: transfer.userInfo) == pending.request.requestId {
                transfer.cancel()
                cancelled = true
            }
        }
        switch pending.resolveCancel(transferCancelled: cancelled) {
        case .cleared:
            clearPending()
        case .keptAsDelivered:
            pendingNewEgg = pending
            try? pendingFile.save(pending)
            status = "이미 워치로 보냈을 수 있어요. 워치에서 새 알이 시작될 수 있어요"
        }
    }

    private nonisolated static func requestId(of userInfo: [String: Any]) -> UUID? {
        guard let data = userInfo[NewEggRequest.userInfoKey] as? Data else { return nil }
        return (try? JSONDecoder().decode(NewEggRequest.self, from: data))?.requestId
    }

    private func transferFinished(requestId: UUID?, failed: Bool) {
        guard var pending = pendingNewEgg, pending.request.requestId == requestId,
              pending.applyTransferResult(failed: failed) else { return }
        pendingNewEgg = pending
        try? pendingFile.save(pending)
    }

    /// After launch: a `.preparing` request whose transfer is not queued is sent again (same request, the watch
    /// ignores a repeated target). A `.queued` one gone from the system queue was already sent while the app was
    /// not running (the finish callback can be missed).
    private func reconcileQueuedRequest() {
        guard var pending = pendingNewEgg else { return }
        let stillQueued = WCSession.default.outstandingUserInfoTransfers.contains {
            Self.requestId(of: $0.userInfo) == pending.request.requestId
        }
        switch pending.reconciliation(stillQueued: stillQueued) {
        case .none:
            break
        case .markDelivered:
            transferFinished(requestId: pending.request.requestId, failed: false)
        case .markQueued, .resend:
            if pending.reconciliation(stillQueued: stillQueued) == .resend {
                guard let data = try? JSONEncoder().encode(pending.request) else { return }
                WCSession.default.transferUserInfo([NewEggRequest.userInfoKey: data])
            }
            pending.phase = .queued
            pendingNewEgg = pending
            try? pendingFile.save(pending)
        }
    }

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        let id = Self.requestId(of: userInfoTransfer.userInfo)
        let failed = error != nil
        Task { @MainActor in self.transferFinished(requestId: id, failed: failed) }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let data = session.receivedApplicationContext["monster_snapshot"] as? Data
        Task { @MainActor in
            self.updateStatus()
            self.receive(data)
            self.reconcileQueuedRequest()
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
