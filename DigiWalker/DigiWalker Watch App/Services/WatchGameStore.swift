import Combine
import DigiWalkerCore
import Foundation

@MainActor
final class WatchGameStore: ObservableObject {
    @Published private(set) var state: GameState?
    @Published private(set) var message: String?
    @Published private(set) var busy = false
    private let file = StateFile<GameState>(url: URL.applicationSupportDirectory.appending(path: "game-state.json"))
    private let health = HealthService()
    private let sync = WatchSyncService()

    func refresh(requestAccess: Bool = false) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            if state == nil {
                if let saved = try file.load() {
                    var updated = saved
                    updated.migrateLegacyStarter()
                    if updated == saved {
                        state = saved
                    } else {
                        try commit(updated)
                    }
                } else {
                    try commit(GameState())
                }
            }
            guard var saved = state else { return }
            sync.publish(saved.snapshot)
            if requestAccess {
                try await health.requestAccess()
                if saved.enrolledAt == nil {
                    saved.enroll(at: .now)
                    try commit(saved)
                }
            }
            guard saved.enrolledAt != nil else { return }
            let candidate = try await health.reconciled(saved, through: .now)
            if candidate != saved {
                try commit(candidate)
                sync.publish(candidate.snapshot)
            }
            message = candidate.todaySteps == nil ? "읽을 수 있는 오늘 걸음 기록이 없어요. 건강 권한을 확인해 주세요." : nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func commit(_ candidate: GameState) throws {
        try file.save(candidate)
        state = candidate
    }
}
