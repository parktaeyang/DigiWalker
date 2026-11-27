import Foundation
import Testing
@testable import DigiWalkerCore

@Suite struct ItemUseTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func settled(seed: UInt64, steps: Int = 75_000) -> GameState {
        var state = GameState.enrolledEgg(id: testPartnerId(seed), at: start)
        var generator = SeededGenerator(seed: seed)
        state.settle(day: start, steps: steps, distance: nil, at: start, using: &generator)
        return state
    }

    private func requiredItem(of speciesId: String) -> String? {
        SpeciesCatalog.cards.lazy.flatMap { $0.stages.joined() }.first { $0.speciesId == speciesId }?.requiredItemId
    }

    private func firstStateWithUse() throws -> GameState {
        try #require((0..<2_000 as Range<UInt64>).lazy.map { settled(seed: $0) }.first { !$0.itemUses.isEmpty })
    }

    private func tampered(_ state: GameState, _ change: (inout [String: Any]) -> Void) throws -> Data {
        var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        change(&root)
        return try JSONSerialization.data(withJSONObject: root)
    }

    @Test func aPickedLockedSpeciesConsumesExactlyOneItemAndOthersConsumeNothing() {
        var sawUse = false, sawNoLocked = false
        for seed in 0..<400 as Range<UInt64> {
            let state = settled(seed: seed)
            let lockedPicks = state.dex.compactMap { entry in requiredItem(of: entry.speciesId).map { (entry.speciesId, $0) } }
            #expect(state.itemUses.map(\.speciesId) == lockedPicks.map(\.0))
            #expect(state.itemUses.map(\.itemId) == lockedPicks.map(\.1))
            #expect(state.itemUses.allSatisfy { $0.monsterId == state.monster.id && $0.usedAt == start })
            for (_, item) in lockedPicks { #expect(state.items.contains { $0.itemId == item }) }
            for item in ItemCatalog.ids {
                let granted = state.items.filter { $0.itemId == item }.count
                let used = state.itemUses.filter { $0.itemId == item }.count
                #expect(state.count(of: item) == granted - used)
            }
            if lockedPicks.isEmpty { sawNoLocked = true } else { sawUse = true }
        }
        #expect(sawUse && sawNoLocked)
    }

    @Test func consumingDoesNotChangeTheNumberOfDraws() {
        for seed in 0..<200 as Range<UInt64> {
            var state = GameState.enrolledEgg(id: testPartnerId(seed), at: start)
            var counting = CountingGenerator(seed: seed)
            state.settle(day: start, steps: 75_000, distance: nil, at: start, using: &counting)
            #expect(counting.draws == 7)
        }
    }

    @Test func usedItemIsGoneFromSummaryAndOwnership() throws {
        let state = try firstStateWithUse()
        let use = try #require(state.itemUses.first)
        let granted = state.items.filter { $0.itemId == use.itemId }.count
        let used = state.itemUses.filter { $0.itemId == use.itemId }.count
        #expect(state.count(of: use.itemId) == granted - used)
        let summary = state.itemSummaries.first { $0.itemId == use.itemId }
        if granted == used {
            #expect(!state.owns(use.itemId))
            #expect(summary == nil)
        } else {
            #expect(summary?.count == granted - used)
        }
        for item in state.itemSummaries {
            #expect(item.count >= 1)
            #expect((0...item.count).contains(item.currentPartnerCount))
        }
    }

    @Test func heldTwoAndUsingOneLeavesOne() throws {
        let base = try firstStateWithUse()
        let use = try #require(base.itemUses.first)
        let rolled = base.itemSegmentsRolled
        let taken = Set(base.items.map(\.segment))
        let spare = try #require((1...rolled).first { !taken.contains($0) })
        let data = try tampered(base) { root in
            var items = root["items"] as! [[String: Any]]
            var extra = items.first { $0["itemId"] as? String == use.itemId }!
            extra["segment"] = spare
            items.append(extra)
            root["items"] = items
        }
        let state = try JSONDecoder().decode(GameState.self, from: data)
        #expect(state.count(of: use.itemId) == base.count(of: use.itemId) + 1)
        #expect(state.owns(use.itemId))
        #expect(state.itemSummaries.first { $0.itemId == use.itemId }?.count == state.count(of: use.itemId))
    }

    @Test func filesWithoutItemUsesReadWithoutRetroactiveConsumption() throws {
        let base = try firstStateWithUse()
        let data = try tampered(base) { $0.removeValue(forKey: "itemUses"); $0.removeValue(forKey: "generation") }
        let loaded = try JSONDecoder().decode(GameState.self, from: data)
        #expect(loaded.itemUses.isEmpty)
        #expect(loaded.generation == 0)
        #expect(loaded.revision == base.revision)
        #expect(loaded.items == base.items)
        #expect(loaded.itemSummaries.map(\.count).reduce(0, +) == base.items.count)
    }

    @Test func damagedItemUsesAreRejected() throws {
        let base = try firstStateWithUse()
        let decode = { (data: Data) in try JSONDecoder().decode(GameState.self, from: data) }
        // More uses than grants.
        let tooMany = try tampered(base) { root in
            var uses = root["itemUses"] as! [[String: Any]]
            var extra = uses[0]
            extra["stage"] = 1
            uses.append(extra)
            root["itemUses"] = uses
            root["items"] = (root["items"] as! [[String: Any]]).filter { ($0["itemId"] as? String) != (uses[0]["itemId"] as? String) }
        }
        #expect(throws: DecodingError.self) { try decode(tooMany) }
        // Duplicate (monsterId, stage).
        let duplicate = try tampered(base) { root in
            var uses = root["itemUses"] as! [[String: Any]]
            uses.append(uses[0])
            root["itemUses"] = uses
        }
        #expect(throws: DecodingError.self) { try decode(duplicate) }
        // Empty id.
        let emptyId = try tampered(base) { root in
            var uses = root["itemUses"] as! [[String: Any]]
            uses[0]["itemId"] = ""
            root["itemUses"] = uses
        }
        #expect(throws: DecodingError.self) { try decode(emptyId) }
        // A stage beyond the partner's stage.
        let tooFar = try tampered(base) { root in
            var uses = root["itemUses"] as! [[String: Any]]
            uses[0]["stage"] = 6
            root["itemUses"] = uses
        }
        #expect(throws: DecodingError.self) { try decode(tooFar) }
        // Null value.
        let null = try tampered(base) { $0["itemUses"] = NSNull() }
        #expect(throws: DecodingError.self) { try decode(null) }
    }

    @Test func stateWithUsesRoundTrips() throws {
        let base = try firstStateWithUse()
        let loaded = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(base))
        #expect(loaded == base)
    }

    @Test func retriesOfAMultiDayBatchGrantTheSameItems() {
        // An already hatched partner passes 75,000 steps and rolls further segments in one batch. Which stage-5
        // species the evolution generator picks (and so which items it uses up) must not change the item draws.
        var compared = 0
        for seed in 0..<400 as Range<UInt64> {
            var base = GameState.enrolledEgg(id: testPartnerId(seed), at: start)
            var first = SeededGenerator(seed: seed)
            base.settle(day: start, steps: 600, distance: nil, at: start, using: &first)
            func retry(_ generatorSeed: UInt64) -> GameState {
                var state = base
                var generator = SeededGenerator(seed: generatorSeed)
                // Day by day inside one reconcile batch: day 3 rolls after day 2's evolutions used items up.
                for (offset, steps) in [(1, 40_000), (2, 50_000), (3, 50_000)] {
                    let day = start.addingTimeInterval(Double(offset) * 86_400)
                    state.settle(day: day, steps: steps, distance: nil, at: day,
                                 committedCardId: base.monster.cardId,
                                 committedUseCount: base.itemUses.count, using: &generator)
                }
                return state
            }
            let results = (0..<12 as Range<UInt64>).map { retry($0 &* 7_919 &+ 11) }
            #expect(results.dropFirst().allSatisfy { $0.items == results[0].items })
            if results.dropFirst().contains(where: { $0.itemUses != results[0].itemUses }) { compared += 1 }
        }
        #expect(compared > 0)
    }

    @Test func itemsAnEarlierPartnerUsedUpAreAgainPreferredForTheNextPartner() throws {
        var found = false
        for seed in 1..<40 as Range<UInt64> {
            var state = GameState.enrolledEgg(id: testPartnerId(seed), at: start)
            var generator = SeededGenerator(seed: seed)
            state.settle(day: start, steps: 85_000, distance: nil, at: start, using: &generator)
            guard state.startNewEgg(target: state.monster.id, at: start, newMonsterId: testPartnerId(900 + seed)) else { continue }
            var hatchGen = SeededGenerator(seed: 1)
            state.settle(day: start, steps: 85_500, distance: nil, at: start, using: &hatchGen)
            let card = try #require(state.monster.card)
            let required = card.requiredItemIds
            guard required.count <= 5 else { continue }
            // Earlier partner holds and has used up every item that would unlock a species on the new card.
            let oldId = testPartnerId(seed)
            let data = try tampered(state) { root in
                var items = root["items"] as! [[String: Any]]
                var uses = root["itemUses"] as? [[String: Any]] ?? []
                items.removeAll { ($0["monsterId"] as? String) == oldId.uuidString }
                uses.removeAll { ($0["monsterId"] as? String) == oldId.uuidString }
                for (i, id) in required.enumerated() {
                    items.append(["itemId": id, "monsterId": oldId.uuidString, "segment": i + 1, "grantedAt": 0])
                    uses.append(["itemId": id, "monsterId": oldId.uuidString, "speciesId": "x", "stage": i + 1, "usedAt": 0])
                }
                root["items"] = items
                root["itemUses"] = uses
            }
            var loaded = try JSONDecoder().decode(GameState.self, from: data)
            let before = loaded.items.count
            var generator2 = SeededGenerator(seed: seed)
            loaded.settle(day: start.addingTimeInterval(86_400), steps: 100_000, distance: nil, at: start,
                          committedCardId: loaded.monster.cardId,
                          committedUseCount: loaded.itemUses.count, using: &generator2)
            let id = loaded.monster.id
            // Only the first new grant is checked: later ones see items this partner has found by then.
            for grant in loaded.items.dropFirst(before).prefix(1) {
                #expect(grant.itemId == ItemDrop.roll(monsterId: id, segment: grant.segment, preferred: required))
            }
            for itemId in required {
                let got = loaded.items.filter { $0.monsterId == id && $0.itemId == itemId }.count
                let used = loaded.itemUses.filter { $0.monsterId == id && $0.itemId == itemId }.count
                #expect(used <= got)
                #expect(loaded.count(of: itemId) >= 0)
            }
            found = found || loaded.items.count > before
        }
        #expect(found)
    }

    @Test func anItemTheCurrentPartnerUsedInACommittedBatchIsAgainPreferred() throws {
        var checked = 0
        for seed in 0..<400 as Range<UInt64> {
            let base = settled(seed: seed, steps: 75_000)
            guard let card = base.monster.card, !base.itemUses.isEmpty else { continue }
            let preferred = card.requiredItemIds.filter { base.count(of: $0) == 0 }
            // At least one required item was granted to and used up by this very partner in the saved state.
            guard base.itemUses.contains(where: { preferred.contains($0.itemId) }) else { continue }
            var next = base
            var generator = SeededGenerator(seed: seed)
            next.settle(day: start, steps: 80_000, distance: nil, at: start,
                        committedCardId: base.monster.cardId, committedUseCount: base.itemUses.count, using: &generator)
            let grant = try #require(next.items.dropFirst(base.items.count).first)
            #expect(grant.itemId == ItemDrop.roll(monsterId: base.monster.id, segment: grant.segment, preferred: preferred))
            checked += 1
        }
        #expect(checked > 0)
    }

    @Test func generationAndItemUsesMustBePresentTogether() throws {
        let base = try firstStateWithUse()
        let noGeneration = try tampered(base) { $0["generation"] = nil }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(GameState.self, from: noGeneration) }
        let noUses = try tampered(base) { $0["itemUses"] = nil }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(GameState.self, from: noUses) }
        let legacy = try tampered(base) { $0["itemUses"] = nil; $0["generation"] = nil }
        let decoded = try JSONDecoder().decode(GameState.self, from: legacy)
        #expect(decoded.itemUses.isEmpty && decoded.generation == 0)
    }

    @Test func settlingTheSameInputAgainOrAfterDecodingKeepsItemUses() throws {
        let base = try firstStateWithUse()
        var again = base
        var generator = SeededGenerator(seed: 99)
        again.settle(day: start, steps: 75_000, distance: nil, at: start, using: &generator)
        #expect(again.itemUses == base.itemUses)
        #expect(again.items == base.items)
        var decoded = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(base))
        var generator2 = SeededGenerator(seed: 5)
        decoded.settle(day: start, steps: 75_000, distance: nil, at: start, using: &generator2)
        #expect(decoded.itemUses == base.itemUses)
        #expect(decoded == base)
    }

    @Test func aUseWithAStageBeyondTheCardIsRejectedEvenForAnEarlierPartner() throws {
        let base = try firstStateWithUse()
        let data = try tampered(base) { root in
            var items = root["items"] as! [[String: Any]]
            var uses = root["itemUses"] as! [[String: Any]]
            let other = testPartnerId(777).uuidString
            items.append(["itemId": "x", "monsterId": other, "segment": 1, "grantedAt": 0])
            uses.append(["itemId": "x", "monsterId": other, "speciesId": "y", "stage": EvolutionCard.stageCount, "usedAt": 0])
            root["items"] = items
            root["itemUses"] = uses
        }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(GameState.self, from: data) }
    }

    @Test func aV3SnapshotIgnoresAnExperienceField() throws {
        let base = try firstStateWithUse()
        var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(base.snapshot)) as? [String: Any])
        var monster = try #require(root["monster"] as? [String: Any])
        monster["experience"] = 123_456
        root["monster"] = monster
        let snapshot = try JSONDecoder().decode(MonsterSnapshot.self, from: JSONSerialization.data(withJSONObject: root))
        #expect(snapshot.schemaVersion == MonsterSnapshot.currentSchemaVersion)
        #expect(snapshot.monster == base.monster)
        #expect(!String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self).contains("experience"))
    }
}
