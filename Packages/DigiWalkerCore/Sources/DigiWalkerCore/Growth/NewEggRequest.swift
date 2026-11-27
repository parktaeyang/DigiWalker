import Foundation

/// A request from the iPhone to the watch to replace the finished partner with a new egg. The watch applies it
/// only if `targetMonsterId` is still the current partner, so a repeated or late request changes nothing.
/// `requestId` is for logs and the pending display, not for idempotency.
public struct NewEggRequest: Codable, Equatable, Sendable {
    /// Key of the JSON `Data` in the `WCSession` userInfo dictionary.
    public static let userInfoKey = "new_egg_request"

    public let requestId: UUID
    public let targetMonsterId: UUID
    public let requestedAt: Date

    public init(requestId: UUID = UUID(), targetMonsterId: UUID, requestedAt: Date) {
        self.requestId = requestId
        self.targetMonsterId = targetMonsterId
        self.requestedAt = requestedAt
    }
}
