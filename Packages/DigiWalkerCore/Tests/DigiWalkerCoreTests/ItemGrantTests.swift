import Foundation
import Testing
@testable import DigiWalkerCore

@Suite struct ItemGrantTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var day2: Date { start.addingTimeInterval(86400) }

    private func enrolled(id: UInt64 = 1) -> GameState {
        GameState.enrolledEgg(id: testPartnerId(id), at: start)
    }

    /// Same state with another partner id, so tests can pick ids with a known drop pattern.
    private func with(monsterId: UUID, _ state: GameState) throws -> GameState {
        var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        var monster = try #require(root["monster"] as? [String: Any])
        monster["id"] = monsterId.uuidString
        root["monster"] = monster
        return try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: root))
    }

    private func tampered(_ state: GameState, _ change: (inout [String: Any]) -> Void) throws -> Data {
        var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        change(&root)
        return try JSONSerialization.data(withJSONObject: root)
    }

    private func settle(_ state: inout GameState, steps: Int, day: Date? = nil, seed: UInt64 = 1) {
        var generator = SeededGenerator(seed: seed)
        state.settle(day: day ?? start, steps: steps, distance: nil, at: day ?? start, using: &generator)
    }

    @Test func eachNewSegmentIsRolledExactlyOnceWithTheDeterministicResult() {
        var state = enrolled()
        settle(&state, steps: 25_000)
        #expect(state.itemSegmentsRolled == 5)
        // The partner was still an egg when rolling (evolution runs after), so the pool is the whole catalog.
        let id = state.monster.id
        let expected = (1...5).compactMap { s in ItemDrop.roll(monsterId: id, segment: s, preferred: []).map { ($0, s) } }
        #expect(state.items.map(\.itemId) == expected.map(\.0))
        #expect(state.items.map(\.segment) == expected.map(\.1))
        #expect(state.items.allSatisfy { $0.monsterId == id && $0.grantedAt == start })
    }

    @Test func rereadingTheSameDayOrLowerValuesOrDistanceGivesNothing() {
        var state = enrolled()
        settle(&state, steps: 12_000)
        let snapshot = state
        settle(&state, steps: 12_000)
        settle(&state, steps: 3_000)
        var generator = SeededGenerator(seed: 5)
        state.settle(day: start, steps: nil, distance: 99_999, at: start, using: &generator)
        #expect(state.items == snapshot.items)
        #expect(state.itemSegmentsRolled == snapshot.itemSegmentsRolled)
        #expect(state.itemSegmentsRolled == 2)
    }

    @Test func nextDayRollsOnlyTheNewSegments() {
        var state = enrolled()
        settle(&state, steps: 9_000)
        #expect(state.itemSegmentsRolled == 1)
        settle(&state, steps: 6_000, day: day2)
        #expect(state.itemSegmentsRolled == 3) // 15,000 total
    }

    @Test func retryAfterAFailedSaveGivesTheSameItems() throws {
        var saved = enrolled()
        settle(&saved, steps: 4_000)
        var first = saved, second = saved
        settle(&first, steps: 60_000, seed: 11)
        // A different evolution generator on the retry must not change the drops.
        settle(&second, steps: 60_000, seed: 12)
        #expect(first.items.map(\.segment) == second.items.map(\.segment))
        #expect(first.itemSegmentsRolled == 12)
        // Save, reload, settle the same readings again: nothing is added twice.
        var reloaded = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(first))
        #expect(reloaded == first)
        settle(&reloaded, steps: 60_000, seed: 13)
        #expect(reloaded.items == first.items)
    }

    @Test func evolutionGeneratorDrawsAreNotConsumedByItems() {
        var state = enrolled()
        var counting = CountingGenerator(seed: 3)
        state.settle(day: start, steps: 30_000, distance: nil, at: start, using: &counting)
        #expect(counting.draws == 5) // card + stage 0, then stages 1...3
        #expect(state.itemSegmentsRolled == 6)
    }

    @Test func dropRateAcrossManyPartnersIsAboutTwentyPercent() {
        var segments = 0, hits = 0
        for seed in 0..<4_000 as Range<UInt64> {
            var state = enrolled(id: seed) // the drop depends on the partner id, so vary it
            settle(&state, steps: 25_000, seed: seed)
            segments += state.itemSegmentsRolled
            hits += state.items.count
        }
        let rate = Double(hits) / Double(segments)
        #expect(segments == 20_000)
        #expect(abs(rate - 0.20) < 0.015, "rate \(rate)")
    }

    @Test func oldSaveWithoutItemKeysGetsNoRetroactiveGrantAndKeepsRevision() throws {
        let state = try LegacyFixtures.gameState(LegacyFixtures.botamon) // 12,010 credited steps
        #expect(state.items.isEmpty)
        #expect(state.itemSegmentsRolled == 2)
        let again = try LegacyFixtures.gameState(LegacyFixtures.botamon)
        #expect(again == state)
        #expect(again.revision == state.revision)
        let egg = try LegacyFixtures.gameState(LegacyFixtures.egg)
        #expect(egg.itemSegmentsRolled == 0)
        // Only segments after the migration point are rolled.
        var grown = state
        var generator = SeededGenerator(seed: 1)
        grown.enroll(at: LegacyFixtures.createdAt)
        grown.settle(day: LegacyFixtures.createdAt.addingTimeInterval(3 * 86400), steps: 3_000, distance: nil, at: nil, using: &generator)
        #expect(grown.itemSegmentsRolled == 3) // 15,010 steps
        #expect(grown.items.allSatisfy { $0.segment == 3 })
    }

    @Test func newKeysRoundTripThroughTheStateFile() throws {
        var state = enrolled()
        settle(&state, steps: 60_000)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("items-\(UUID().uuidString)/state.json")
        let file = StateFile<GameState>(url: url)
        try file.save(state)
        let loaded = try #require(try file.load())
        #expect(loaded == state)
        #expect(loaded.items == state.items)
        #expect(loaded.snapshot.items == state.itemSummaries)
    }

    @Test func countsDuplicatesAndOwnership() throws {
        let id = testPartnerId(2)
        var state = enrolled(id: 2)
        settle(&state, steps: 20_000) // 4 segments rolled
        let data = try tampered(state) {
            $0["items"] = [1, 3].map { ["itemId": "digicore", "monsterId": id.uuidString, "segment": $0, "grantedAt": 5.0] }
        }
        let loaded = try JSONDecoder().decode(GameState.self, from: data)
        #expect(loaded.count(of: "digicore") == 2)
        #expect(loaded.owns("digicore") && !loaded.owns("digicode"))
        #expect(loaded.count(of: "digicode") == 0)
    }

    @Test func corruptItemsAreRejected() throws {
        let id = testPartnerId(3)
        var state = enrolled(id: 3)
        settle(&state, steps: 15_000) // 3 segments rolled
        func grant(_ segment: Int, monster: UUID? = nil) -> [String: Any] {
            ["itemId": "digicore", "monsterId": (monster ?? id).uuidString, "segment": segment, "grantedAt": 5.0]
        }
        let bad: [(String, [String: Any])] = [
            ("duplicate", ["items": [grant(1), grant(1)]]),
            ("beyond rolled", ["items": [grant(4)]]),
            ("segment zero", ["items": [grant(0)]]),
            ("negative rolled", ["itemSegmentsRolled": -1, "items": [] as [Any]]),
            ("blank id", ["items": [["itemId": "", "monsterId": id.uuidString, "segment": 1, "grantedAt": 5.0]]]),
            ("checkpoint ahead", ["itemSegmentsRolled": 4, "items": [] as [Any]]),
            ("checkpoint behind", ["itemSegmentsRolled": 2, "items": [] as [Any]]),
            ("items null", ["items": NSNull()]),
            ("rolled null", ["itemSegmentsRolled": NSNull()]),
        ]
        for (name, keys) in bad {
            let data = try tampered(state) { root in keys.forEach { root[$0.key] = $0.value } }
            #expect(throws: DecodingError.self, "\(name)") { try JSONDecoder().decode(GameState.self, from: data) }
        }
        // Only one of the two keys is a damaged save; both missing is an old file.
        for key in ["items", "itemSegmentsRolled"] {
            let data = try tampered(state) { $0[key] = nil }
            #expect(throws: DecodingError.self, "only \(key) missing") { try JSONDecoder().decode(GameState.self, from: data) }
        }
        let old = try tampered(state) { $0["items"] = nil; $0["itemSegmentsRolled"] = nil }
        #expect(try JSONDecoder().decode(GameState.self, from: old).itemSegmentsRolled == 3)
        // Another partner's earlier grants keep their own segment numbers and are not tied to the current checkpoint.
        let other = try tampered(state) { $0["items"] = [grant(7, monster: testPartnerId(99)), grant(1)] }
        #expect(throws: Never.self) { try JSONDecoder().decode(GameState.self, from: other) }
    }

    @Test func unknownItemIdsStayReadable() throws {
        let id = testPartnerId(4)
        var state = enrolled(id: 4)
        settle(&state, steps: 5_000)
        let data = try tampered(state) {
            $0["items"] = [["itemId": "future_item", "monsterId": id.uuidString, "segment": 1, "grantedAt": 5.0]]
        }
        let loaded = try JSONDecoder().decode(GameState.self, from: data)
        #expect(loaded.owns("future_item"))
    }

    @MainActor @Test func retryOfAMultiDayReconcileGivesTheSameSegmentsAndItems() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let secondDay = calendar.startOfDay(for: day2)
        let now = day2.addingTimeInterval(3_600)
        var compared = 0
        for id in 1...40 as ClosedRange<UInt64> {
            var cards = Set<String>()
            var results: [[ItemGrant]] = []
            for seed in [1 as UInt64, 2, 3, 4, 5, 6] {
                let saved = enrolled(id: id)
                let state = try await GrowthService.reconcile(saved, through: now, random: SeededGenerator(seed: seed)) { metric, from, _ in
                    guard metric == .steps else { return nil }
                    return from < secondDay ? 1_000 : 120_000 // hatches on day 1, rolls everything on day 2
                }
                cards.insert(state.monster.cardId ?? "")
                results.append(state.items)
                #expect(state.itemSegmentsRolled == 24)
            }
            #expect(cards.count > 1, "the retries must differ in the hatch card for this test to mean anything")
            #expect(results.dropFirst().allSatisfy { $0.map(\.segment) == results[0].map(\.segment) && $0.map(\.itemId) == results[0].map(\.itemId) })
            compared += results[0].count
        }
        #expect(compared > 0)
    }

    @Test func aCardFixedInAnEarlierSettlementSteersTheDrops() throws {
        var steered = 0
        for id in 1...200 as ClosedRange<UInt64> {
            var state = enrolled(id: id)
            settle(&state, steps: 600, seed: id) // hatches; the card is fixed at `start`
            let card = try #require(state.monster.card)
            var owned = Set<String>()
            settle(&state, steps: 100_000, day: day2, seed: id)
            for segment in 1...20 {
                let preferred = card.requiredItemIds.filter { !owned.contains($0) }
                let expected = ItemDrop.roll(monsterId: state.monster.id, segment: segment, preferred: preferred)
                #expect(state.items.first { $0.segment == segment }?.itemId == expected, "id \(id) segment \(segment)")
                if let expected { owned.insert(expected); if preferred.contains(expected) { steered += 1 } }
            }
        }
        #expect(steered > 0)
    }

    @Test func aBackwardsClockDoesNotChangeWhichCardSteersTheDrops() throws {
        var steered = 0
        for id in 1...200 as ClosedRange<UInt64> {
            var state = enrolled(id: id)
            settle(&state, steps: 600, seed: id) // hatches at `start`
            let card = try #require(state.monster.card)
            var generator = SeededGenerator(seed: id)
            // The settlement time is a day before the card was fixed (clock set back).
            state.settle(day: day2, steps: 100_000, distance: nil, at: start.addingTimeInterval(-86_400), using: &generator)
            var owned = Set<String>()
            for segment in 1...20 {
                let preferred = card.requiredItemIds.filter { !owned.contains($0) }
                let expected = ItemDrop.roll(monsterId: state.monster.id, segment: segment, preferred: preferred)
                #expect(state.items.first { $0.segment == segment }?.itemId == expected, "id \(id) segment \(segment)")
                if let expected { owned.insert(expected); if preferred.contains(expected) { steered += 1 } }
            }
        }
        #expect(steered > 0)
    }
}

// MARK: - Evolution gate

extension ItemGrantTests {
    private static let lockedItems: [String: String] = [
        "donedevimon": "digicore", "rapidmon_armor": "digimental_fate", "sakuyamon_x": "x_antibody",
        "lordknightmon": "digicore", "dynasmon": "digicore", "murmukusmon": "digicode",
        "lucemon_falldown": "digicode",
    ]

    @Test func lockedSpeciesAppearOnlyWithTheirItemEvenWhenTheItemWasFoundInTheSameSettlement() {
        var reachedLocked = 0
        for seed in 0..<6_000 as Range<UInt64> {
            var state = enrolled(id: seed)
            settle(&state, steps: 75_000, seed: seed)
            #expect(state.monster.stage == 5)
            for entry in state.dex {
                if let item = Self.lockedItems[entry.speciesId] {
                    #expect(state.owns(item), "\(entry.speciesId) without \(item)")
                    reachedLocked += 1
                }
            }
        }
        // Reachable at all: stage 5 of locked cards is 1/3...1/4 once the item is owned.
        #expect(reachedLocked > 0)
    }

    @Test func gatedPickStillConsumesOneDrawPerStage() {
        for seed in 0..<50 as Range<UInt64> {
            var state = enrolled(id: seed)
            var counting = CountingGenerator(seed: seed)
            state.settle(day: start, steps: 75_000, distance: nil, at: start, using: &counting)
            #expect(counting.draws == 7) // card + stage 0, then stages 1...5
        }
    }

    @Test func existingLockedPartnersAreNotReverted() throws {
        var state = enrolled()
        settle(&state, steps: 1_000)
        let data = try tampered(state) { root in
            var monster = root["monster"] as! [String: Any]
            monster["cardId"] = "terrier_ex"
            monster["speciesId"] = "rapidmon_armor"
            monster["name"] = "래피드몬(아머)"
            root["monster"] = monster
        }
        var loaded = try JSONDecoder().decode(GameState.self, from: data)
        #expect(!loaded.owns("digimental_fate"))
        settle(&loaded, steps: 100_000, day: day2)
        #expect(loaded.monster.speciesId == "rapidmon_armor")
    }
}
