import Foundation
import WatchKit

/// Keeps a single app refresh request pending, about 45 minutes out. The system decides the actual time.
struct RefreshScheduler: RefreshScheduling {
    static let interval: TimeInterval = 45 * 60

    func scheduleNextRefresh() {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date(timeIntervalSinceNow: Self.interval), userInfo: nil
        ) { @Sendable error in
            if let error { NSLog("DigiWalker: refresh scheduling failed (%@)", error.localizedDescription) }
        }
    }
}
