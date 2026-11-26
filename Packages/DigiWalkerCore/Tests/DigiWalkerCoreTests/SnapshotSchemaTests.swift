import Foundation
import Testing
@testable import DigiWalkerCore

@Suite struct SnapshotSchemaTests {
    private let start = LegacyFixtures.createdAt

    private func hatched() -> GameState {
        var state = GameState.fixedEgg(now: start)
        state.enroll(at: start)
        var generator = SeededGenerator(seed: 8)
        state.settle(day: start, steps: 1600, distance: 10, using: &generator)
        return state
    }

    private func v2(_ state: GameState, dex: [DexEntry]?, version: Int = 2) -> MonsterSnapshot {
        MonsterSnapshot(schemaVersion: version, revision: state.revision, createdAt: state.createdAt,
                        monster: state.monster, todaySteps: nil, observedAt: nil, timeZone: .gmt, dex: dex)
    }

    @Test func publishesV3WithDexAndCard() throws {
        let state = hatched()
        let snapshot = state.snapshot
        #expect(snapshot.schemaVersion == 3)
        #expect(snapshot.items == state.itemSummaries)
        #expect(snapshot.dex == state.dex)
        #expect(snapshot.monster.cardId == state.monster.cardId)
        #expect(snapshot.supersedes(nil))
        let decoded = try JSONDecoder().decode(MonsterSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
    }

    @Test func rejectsFutureVersion() {
        let state = hatched()
        #expect(!v2(state, dex: state.dex, version: 4).supersedes(nil))
        #expect(!v2(state, dex: state.dex, version: 0).supersedes(nil))
    }

    @Test func rejectsInvalidDex() {
        let state = hatched()
        let first = state.dex[0]
        #expect(!v2(state, dex: nil).supersedes(nil))
        #expect(!v2(state, dex: []).supersedes(nil))
        #expect(!v2(state, dex: state.dex + [first]).supersedes(nil))
        #expect(!v2(state, dex: Array(state.dex.dropLast())).supersedes(nil)) // current species missing
        let negative = DexEntry(speciesId: "extra", firstMetAt: start, firstMetSteps: -1, cardId: nil)
        #expect(!v2(state, dex: state.dex + [negative]).supersedes(nil))
        let blank = DexEntry(speciesId: "", firstMetAt: start, firstMetSteps: 0, cardId: nil)
        #expect(!v2(state, dex: state.dex + [blank]).supersedes(nil))
        #expect(v2(state, dex: state.dex).supersedes(nil))
    }

    @Test func v1WithoutDexIsAccepted() throws {
        let snapshot = try JSONDecoder().decode(MonsterSnapshot.self, from: Data(LegacyFixtures.snapshotV1.utf8))
        #expect(snapshot.supersedes(nil))
        let reencoded = try JSONDecoder().decode(MonsterSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(reencoded == snapshot)
    }

    @Test func v1CarryingADexIsRejected() {
        let state = hatched()
        #expect(!v2(state, dex: state.dex, version: 1).supersedes(nil))
        #expect(v2(state, dex: nil, version: 1).supersedes(nil))
    }

    @Test func v2ReplacesV1CacheOfTheSameMonster() throws {
        var state = try LegacyFixtures.gameState(LegacyFixtures.botamon)
        let cachedV1 = MonsterSnapshot(schemaVersion: 1, revision: state.revision, createdAt: state.createdAt,
                                       monster: state.monster, todaySteps: nil, observedAt: nil, timeZone: .gmt)
        #expect(cachedV1.supersedes(nil))
        var generator = SeededGenerator(seed: 6)
        state.migrateToEvolutionCatalog(at: start, using: &generator)
        #expect(state.snapshot.supersedes(cachedV1))
        #expect(!cachedV1.supersedes(state.snapshot))
        #expect(!state.snapshot.supersedes(state.snapshot))
    }

    @Test func fullDexSnapshotStaysSmall() throws {
        let state = hatched()
        let entries = (SpeciesCatalog.dexUniverse(includingLegacy: true)).map {
            DexEntry(speciesId: $0, firstMetAt: start, firstMetSteps: 3000,
                     cardId: EvolutionCard.cards(containing: $0).map(\.id).max { $0.count < $1.count })
        }
        #expect(entries.count == 185)
        let big = MonsterSnapshot(schemaVersion: 2, revision: 1, createdAt: start,
                                  monster: state.monster, todaySteps: 1, observedAt: start, timeZone: .gmt,
                                  dex: entries)
        let size = try JSONEncoder().encode(big).count
        #expect(size < 32 * 1024, "size \(size)") // 185 entries: ~17 KB measured
    }

    /// Re-encodes a hatched state with the monster's card and species replaced.
    private func tampered(cardId: String?, speciesId: String?) throws -> Data {
        let state = hatched()
        var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        var monster = try #require(root["monster"] as? [String: Any])
        if let cardId { monster["cardId"] = cardId }
        if let speciesId { monster["speciesId"] = speciesId }
        root["monster"] = monster
        return try JSONSerialization.data(withJSONObject: root)
    }

    @Test func decodingRejectsUnknownCardOrSpeciesOffCard() throws {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(GameState.self, from: tampered(cardId: "nope_ex", speciesId: nil)) }
        // Wargreymon belongs to agu_ex only; a known species that is not on the card is damaged.
        let state = hatched()
        let other = state.monster.cardId == "guil_ex" ? "gabu_ex" : "guil_ex"
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(GameState.self, from: tampered(cardId: other, speciesId: "wargreymon")) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(GameState.self, from: tampered(cardId: "agu_ex", speciesId: "digitama")) }
    }

    @Test func decodingKeepsUnknownSpeciesAndLegacyStates() throws {
        _ = try JSONDecoder().decode(GameState.self, from: tampered(cardId: "agu_ex", speciesId: "someday_mon"))
        for json in [LegacyFixtures.egg, LegacyFixtures.botamon, LegacyFixtures.punimon] {
            _ = try LegacyFixtures.gameState(json)
        }
        _ = try JSONDecoder().decode(GameState.self, from: tampered(cardId: nil, speciesId: nil))
    }

    @Test func decodingRejectsModernSaveOfAdvancedSpeciesWithoutCard() throws {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GameState.self, from: tampered(removeCard: true, speciesId: "greymon"))
        }
        // Stage 0 species and unknown species without a card keep decoding.
        _ = try JSONDecoder().decode(GameState.self, from: tampered(removeCard: true, speciesId: "botamon"))
        _ = try JSONDecoder().decode(GameState.self, from: tampered(removeCard: true, speciesId: "someday_mon"))
    }

    @Test func newCardStatesDecodeAndExistingGabumonStateIsUnchangedByMigration() throws {
        for (card, species) in [("wolf_ex", "botamon"), ("louwe_ex", "lucemon_falldown"),
                                ("gabu_ex", "punimon"), ("agni_ex", "susanoomon")] {
            let state = try JSONDecoder().decode(GameState.self, from: tampered(cardId: card, speciesId: species))
            #expect(state.monster.cardId == card)
            #expect(state.monster.speciesId == species)
        }
        // A genuine gabu_ex/punimon state (as the existing owner's) round-trips and migration leaves it alone.
        var before: GameState?
        for seed in 0..<300 as Range<UInt64> {
            var state = GameState.fixedEgg(now: start)
            state.enroll(at: start)
            var generator = SeededGenerator(seed: seed)
            state.settle(day: start, steps: 600, distance: 10, using: &generator)
            if state.monster.cardId == "gabu_ex" { before = state; break }
        }
        let original = try #require(before)
        #expect(original.monster.speciesId == "punimon")
        let decoded = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
        var after = decoded
        var generator = SeededGenerator(seed: 4)
        after.migrateToEvolutionCatalog(at: start, using: &generator)
        #expect(after == original)
        #expect(after.revision == original.revision)
    }

    @Test func fixedPreExpansionGabumonFilesKeepEveryValue() throws {
        let id = try #require(UUID(uuidString: "3F2A9C1E-5B7D-4E86-9A10-6C4D8E2F7B35"))
        var state = try LegacyFixtures.gameState(LegacyFixtures.gabuPunimonState)
        let before = state
        var generator = SeededGenerator(seed: 4)
        state.migrateToEvolutionCatalog(at: start, using: &generator)
        #expect(state == before)
        #expect(state.revision == 4)
        #expect(state.monster.id == id)
        #expect(state.monster.cardId == "gabu_ex")
        #expect(state.monster.speciesId == "punimon")
        #expect(state.monster.experience == 60)
        #expect(state.monster.totalCreditedSteps == 600)
        #expect(state.dex.map(\.speciesId) == ["digitama", "punimon"])
        #expect(state.dex.map(\.cardId) == [nil, "gabu_ex"])
        #expect(state.dex.map(\.firstMetSteps) == [0, 500])
        #expect(state.ledgers.values.map(\.creditedSteps) == [600])
        #expect(state.ledgers.values.map(\.creditedXP) == [60])

        let snapshot = try JSONDecoder().decode(MonsterSnapshot.self, from: Data(LegacyFixtures.gabuPunimonSnapshotV2.utf8))
        #expect(snapshot.supersedes(nil))
        #expect(snapshot.schemaVersion == 2)
        #expect(snapshot.revision == 4)
        #expect(snapshot.monster == state.monster)
        #expect(snapshot.dex == state.dex)
        // The watch now publishes v3; the stored v2 snapshot stays valid and carries no items.
        #expect(snapshot.items == nil)
        #expect(state.snapshot.schemaVersion == 3)
        // Same partner and revision: the v3 upgrade replaces the cached v2, never the other way round.
        #expect(state.snapshot.revision == snapshot.revision)
        #expect(state.snapshot.supersedes(snapshot))
        #expect(!snapshot.supersedes(state.snapshot))
        #expect(!state.snapshot.supersedes(state.snapshot))
    }

    @Test func speciesOfAnotherCardIsRejected() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GameState.self, from: tampered(cardId: "wolf_ex", speciesId: "koromon"))
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GameState.self, from: tampered(cardId: "louwe_ex", speciesId: "greymon"))
        }
        // Susanoomon sits on agni_ex and wolf_ex only.
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GameState.self, from: tampered(cardId: "terrier_ex", speciesId: "susanoomon"))
        }
    }

    @Test func legacyBotamonWithoutCardMigratesToAguEX() throws {
        var state = try LegacyFixtures.gameState(LegacyFixtures.botamon)
        var generator = SeededGenerator(seed: 12)
        state.migrateToEvolutionCatalog(at: start, using: &generator)
        #expect(state.monster.cardId == "agu_ex")
        #expect(state.dex.allSatisfy { $0.cardId == nil || $0.cardId == "agu_ex" })
    }

    @Test func newCardMonsterSnapshotIsAcceptedAtSchemaV3() throws {
        #expect(MonsterSnapshot.currentSchemaVersion == 3)
        var found = false
        for seed in 0..<200 as Range<UInt64> {
            var state = GameState.fixedEgg(now: start)
            state.enroll(at: start)
            var generator = SeededGenerator(seed: seed)
            state.settle(day: start, steps: 12_000, distance: 10, using: &generator)
            guard state.monster.cardId == "louwe_ex" || state.monster.cardId == "wolf_ex" else { continue }
            let snapshot = state.snapshot
            #expect(snapshot.schemaVersion == 3)
            #expect(snapshot.supersedes(nil))
            let decoded = try JSONDecoder().decode(MonsterSnapshot.self, from: JSONEncoder().encode(snapshot))
            #expect(decoded == snapshot)
            found = true
            break
        }
        #expect(found)
    }

    private func tampered(removeCard: Bool, speciesId: String) throws -> Data {
        var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(hatched())) as? [String: Any])
        var monster = try #require(root["monster"] as? [String: Any])
        if removeCard { monster["cardId"] = nil }
        monster["speciesId"] = speciesId
        root["monster"] = monster
        return try JSONSerialization.data(withJSONObject: root)
    }
}
