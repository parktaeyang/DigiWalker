import Foundation

/// A single item received at one 5,000-step segment of one partner. `(monsterId, segment)` is unique.
public struct ItemGrant: Codable, Equatable, Sendable {
    public let itemId: String
    public let monsterId: UUID
    /// 1-based index of the 5,000-step segment of the partner's credited steps.
    public let segment: Int
    public let grantedAt: Date

    public init(itemId: String, monsterId: UUID, segment: Int, grantedAt: Date) {
        self.itemId = itemId
        self.monsterId = monsterId
        self.segment = segment
        self.grantedAt = grantedAt
    }
}

/// One item consumed by an evolution into `speciesId` at `stage`. `(monsterId, stage)` is unique.
public struct ItemUse: Codable, Equatable, Sendable {
    public let itemId: String
    public let monsterId: UUID
    public let speciesId: String
    public let stage: Int
    public let usedAt: Date

    public init(itemId: String, monsterId: UUID, speciesId: String, stage: Int, usedAt: Date) {
        self.itemId = itemId
        self.monsterId = monsterId
        self.speciesId = speciesId
        self.stage = stage
        self.usedAt = usedAt
    }
}

/// Per-item summary sent to the iPhone. `count` is the number currently held (grants minus uses), at least 1.
/// `currentPartnerCount` is the part of it found by the current partner.
public struct ItemSummary: Codable, Equatable, Sendable {
    public let itemId: String
    public let count: Int
    public let firstGrantedAt: Date
    public let currentPartnerCount: Int

    public init(itemId: String, count: Int, firstGrantedAt: Date, currentPartnerCount: Int) {
        self.itemId = itemId
        self.count = count
        self.firstGrantedAt = firstGrantedAt
        self.currentPartnerCount = currentPartnerCount
    }
}

/// Deterministic item drop. It never touches the evolution generator, and it does not use `Hasher`
/// (seeded per launch), so the same partner and segment always give the same draw on every platform.
public enum ItemDrop {
    public static let stepsPerSegment = 5_000
    /// Chance of a drop per segment is `successNumerator / successDenominator`.
    static let successNumerator: UInt64 = 1
    static let successDenominator: UInt64 = 5

    public static func segment(forSteps steps: Int) -> Int { max(0, steps) / stepsPerSegment }

    /// Returns the item id dropped at `segment`, or nil. 20% drop; then 50% choose from `preferred`
    /// (if any), else uniformly from the whole catalog. All three draws are always taken so the outcome of one
    /// stage never depends on another.
    public static func roll(monsterId: UUID, segment: Int, preferred: [String]) -> String? {
        var rng = SplitMix64(seed: seed(monsterId: monsterId, segment: segment))
        let hit = rng.next().multipliedFullWidth(by: successDenominator).high < successNumerator
        let usePreferred = rng.next() >> 63 == 0
        let pickDraw = rng.next()
        guard hit else { return nil }
        let pool = usePreferred && !preferred.isEmpty ? preferred : ItemCatalog.ids
        return pool[Int(pickDraw.multipliedFullWidth(by: UInt64(pool.count)).high)]
    }

    static func seed(monsterId: UUID, segment: Int) -> UInt64 {
        let b = monsterId.uuid
        var high: UInt64 = 0, low: UInt64 = 0
        for byte in [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7] { high = high << 8 | UInt64(byte) }
        for byte in [b.8, b.9, b.10, b.11, b.12, b.13, b.14, b.15] { low = low << 8 | UInt64(byte) }
        var mix = SplitMix64(seed: high)
        return mix.next() ^ low ^ (UInt64(max(0, segment)) &* 0x9E37_79B9_7F4A_7C15)
    }
}

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
