import Foundation
import Testing
@testable import DigiWalkerCore

@Suite struct SnapshotSchemaTests {
    private let start = LegacyFixtures.createdAt

    private func hatched() -> GameState {
        var state = GameState(now: start, timeZone: .gmt)
        state.enroll(at: start)
        var generator = SeededGenerator(seed: 8)
        state.settle(day: start, steps: 1600, distance: 10, using: &generator)
        return state
    }

    private func v2(_ state: GameState, dex: [DexEntry]?, version: Int = 2) -> MonsterSnapshot {
        MonsterSnapshot(schemaVersion: version, revision: state.revision, createdAt: state.createdAt,
                        monster: state.monster, todaySteps: nil, observedAt: nil, timeZone: .gmt, dex: dex)
    }

    @Test func publishesV2WithDexAndCard() throws {
        let state = hatched()
        let snapshot = state.snapshot
        #expect(snapshot.schemaVersion == 2)
        #expect(snapshot.dex == state.dex)
        #expect(snapshot.monster.cardId == state.monster.cardId)
        #expect(snapshot.supersedes(nil))
        let decoded = try JSONDecoder().decode(MonsterSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
    }

    @Test func rejectsFutureVersion() {
        let state = hatched()
        #expect(!v2(state, dex: state.dex, version: 3).supersedes(nil))
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
            DexEntry(speciesId: $0, firstMetAt: start, firstMetSteps: 3000, cardId: "guil_ex")
        }
        #expect(entries.count == 51)
        let big = MonsterSnapshot(schemaVersion: 2, revision: 1, createdAt: start,
                                  monster: state.monster, todaySteps: 1, observedAt: start, timeZone: .gmt,
                                  dex: entries)
        let size = try JSONEncoder().encode(big).count
        #expect(size < 16 * 1024)
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

    private func tampered(removeCard: Bool, speciesId: String) throws -> Data {
        var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(hatched())) as? [String: Any])
        var monster = try #require(root["monster"] as? [String: Any])
        if removeCard { monster["cardId"] = nil }
        monster["speciesId"] = speciesId
        root["monster"] = monster
        return try JSONSerialization.data(withJSONObject: root)
    }
}
