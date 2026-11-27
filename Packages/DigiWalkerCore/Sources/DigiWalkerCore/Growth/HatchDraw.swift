import Foundation

/// Deterministic hatching for a new egg: the same partner id always gives the same card on every platform.
/// It never touches the evolution generator, so the draw count of later evolutions is unchanged.
enum HatchDraw {
    private static let salt: UInt64 = 0x4E45_5745_4747_0001

    /// Picks a card other than `excluding` (all cards if it is nil or unknown), then one of its stage 0 species.
    static func pick(monsterId: UUID, excluding: String?) -> (EvolutionCard, CardSlot)? {
        var rng = SplitMix64(seed: ItemDrop.seed(monsterId: monsterId, segment: 0) ^ salt)
        let all = SpeciesCatalog.cards
        let others = all.filter { $0.id != excluding }
        let cards = others.isEmpty ? all : others
        guard let card = pick(cards, using: &rng), let slot = pick(card.eligible(stage: 0), using: &rng) else { return nil }
        return (card, slot)
    }

    private static func pick<T>(_ items: [T], using rng: inout SplitMix64) -> T? {
        guard !items.isEmpty else { return nil }
        let index = rng.next().multipliedFullWidth(by: UInt64(items.count)).high
        return items[Int(index)]
    }
}
