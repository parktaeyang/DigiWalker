import DigiWalkerCore
import Foundation
import UserNotifications
import WatchKit

enum NotificationFailure: LocalizedError {
    case notAuthorized
    var errorDescription: String? { "알림 권한이 없어요." }
}

/// Foreground haptic and background local notification for hatches and evolutions.
struct GrowthNotifier: GrowthAnnouncing {
    /// One identifier per transition, so registering the same one twice leaves a single notification.
    static func identifier(for event: GrowthEvent) -> String {
        "growth-\(event.monsterId.uuidString)-\(event.toSpeciesId)"
    }

    func playHaptic(for event: GrowthEvent) {
        // Hatch and evolution share one success haptic.
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
        try await center.add(UNNotificationRequest(identifier: Self.identifier(for: event), content: content, trigger: nil))
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
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
