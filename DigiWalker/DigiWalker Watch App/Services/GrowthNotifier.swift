import DigiWalkerCore
import Foundation
import UserNotifications
import WatchKit

enum NotificationFailure: LocalizedError {
    case notAuthorized
    var errorDescription: String? { "알림 권한이 없어요." }
}

/// Foreground haptic and background local notification for hatches, evolutions, item finds and the new-egg offer.
struct GrowthNotifier: GrowthAnnouncing {
    nonisolated static let newEggCategory = "NEW_EGG"
    nonisolated static let newEggStartAction = "NEW_EGG_START"
    nonisolated static let newEggKeepAction = "NEW_EGG_KEEP"
    nonisolated static let monsterIdKey = "monsterId"

    /// One identifier per transition (or per item segment, or per partner for the new-egg offer), so registering the
    /// same one twice leaves a single notification and the offer never collides with an evolution notification.
    static func identifier(for event: GrowthEvent) -> String {
        if event.kind == .itemFound, let segment = event.segment {
            return "item-\(event.monsterId.uuidString)-\(segment)"
        }
        if event.kind == .newEggReady { return newEggIdentifier(monsterId: event.monsterId) }
        return "growth-\(event.monsterId.uuidString)-\(event.toSpeciesId)"
    }

    static func newEggIdentifier(monsterId: UUID) -> String { "newegg-\(monsterId.uuidString)" }

    /// Registers the new-egg actions. "Keep" only closes the notification: nothing is stored for it.
    static func registerCategories() {
        let start = UNNotificationAction(identifier: newEggStartAction, title: "새 알 키우기", options: [.foreground])
        let keep = UNNotificationAction(identifier: newEggKeepAction, title: "궁극체 유지", options: [])
        let category = UNNotificationCategory(identifier: newEggCategory, actions: [start, keep],
                                              intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// The partner a tap or the "new egg" action asks about; nil for "keep", dismissal and other notifications.
    nonisolated static func newEggTarget(category: String, action: String, userInfo: [AnyHashable: Any]) -> UUID? {
        guard category == newEggCategory,
              action == newEggStartAction || action == UNNotificationDefaultActionIdentifier,
              let raw = userInfo[monsterIdKey] as? String else { return nil }
        return UUID(uuidString: raw)
    }

    func playHaptic(for event: GrowthEvent) {
        // Hatch, evolution and item finds share one success haptic.
        WKInterfaceDevice.current().play(.success)
    }

    func notify(_ event: GrowthEvent) async throws {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: break
        default: throw NotificationFailure.notAuthorized
        }
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.body
        content.sound = .default
        if event.kind == .newEggReady {
            content.categoryIdentifier = Self.newEggCategory
            content.userInfo = [Self.monsterIdKey: event.monsterId.uuidString]
        }
        try await center.add(UNNotificationRequest(identifier: Self.identifier(for: event), content: content, trigger: nil))
    }

    func withdraw(identifiers: [String]) {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default: return false
        }
    }
}

/// Growth notifications are only registered while the app is not active, but the app can still be on screen
/// (wrist down with always-on display), so they must present themselves instead of being swallowed.
final class GrowthNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let game: WatchGameStore

    init(game: WatchGameStore) {
        self.game = game
    }

    /// "New egg" (or a tap on the offer) asks the store for the confirmation dialog; it never starts a new egg
    /// by itself. "Keep", dismissal and other notifications do nothing.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        guard let target = GrowthNotifier.newEggTarget(category: content.categoryIdentifier,
                                                       action: response.actionIdentifier,
                                                       userInfo: content.userInfo) else { return }
        await game.requestNewEggConfirmation(for: target)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
