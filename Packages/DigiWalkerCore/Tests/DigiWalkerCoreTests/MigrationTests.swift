import Foundation
import Testing
@testable import DigiWalkerCore

@Suite struct MigrationTests {
    private let migratedAt = Date(timeIntervalSince1970: 1_800_100_000)

    private func migrate(_ json: String, seed: UInt64 = 1) throws -> (before: GameState, after: GameState) {
        let before = try LegacyFixtures.gameState(json)
        var after = before
        var generator = SeededGenerator(seed: seed)
        after.migrateToEvolutionCatalog(at: migratedAt, using: &generator)
        return (before, after)
    }

    @Test func legacyJSONDecodesAndRoundTrips() throws {
        for json in [LegacyFixtures.egg, LegacyFixtures.botamon, LegacyFixtures.punimon,
                     LegacyFixtures.poyomon800, LegacyFixtures.poyomon1600, LegacyFixtures.unknown] {
            let state = try LegacyFixtures.gameState(json)
            #expect(state.dex.isEmpty)
            #expect(state.monster.cardId == nil)
            #expect(state.ledgers.count == 2)
            let again = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(state))
            #expect(again == state)
        }
        let egg = try LegacyFixtures.gameState(LegacyFixtures.egg)
        #expect(egg.monster.totalCreditedSteps == 19)
        #expect(egg.revision == 3)
        #expect(egg.createdAt == LegacyFixtures.createdAt)
        #expect(egg.timeZone == .gmt)
    }

    @Test func legacySnapshotJSONDecodesAndIsAccepted() throws {
        let snapshot = try JSONDecoder().decode(MonsterSnapshot.self, from: Data(LegacyFixtures.snapshotV1.utf8))
        #expect(snapshot.schemaVersion == 1)
        #expect(snapshot.dex == nil)
        #expect(snapshot.monster.cardId == nil)
        #expect(snapshot.supersedes(nil))
    }

    @Test func eggBelowThresholdGetsDexOnly() throws {
        let (before, after) = try migrate(LegacyFixtures.egg)
        #expect(after.monster == before.monster)
        #expect(after.dex.map(\.speciesId) == ["digitama"])
        #expect(after.dex.first?.firstMetAt == before.createdAt)
        #expect(after.dex.first?.firstMetSteps == 0)
        #expect(after.revision == before.revision + 1)
        #expect(after.ledgers == before.ledgers)
    }

    @Test func botamonBecomesAguExCardAndEvolvesToStageOne() throws {
        let (before, after) = try migrate(LegacyFixtures.botamon)
        #expect(after.monster.cardId == "agu_ex")
        #expect(after.monster.stage == 1)
        #expect(after.monster.speciesId == "koromon")
        #expect(after.dex.map(\.speciesId) == ["digitama", "botamon", "koromon"])
        #expect(after.dex.map(\.firstMetSteps) == [0, 500, EvolutionCard.requiredSteps(stage: 1)])
        #expect(after.monster.id == before.monster.id)
        #expect(after.monster.experience == before.monster.experience)
        #expect(after.monster.totalCreditedSteps == before.monster.totalCreditedSteps)
        #expect(after.ledgers == before.ledgers)
        #expect(after.monster.distanceMeters == before.monster.distanceMeters)
        #expect(after.snapshot.supersedes(before.snapshot))
    }

    @Test func punimonBecomesGabuExCard() throws {
        let (_, after) = try migrate(LegacyFixtures.punimon)
        #expect(after.monster.cardId == "gabu_ex")
        #expect(after.monster.speciesId == "punimon")
        #expect(after.dex.map(\.speciesId) == ["digitama", "punimon"])
    }

    @Test func poyomonIsReassignedToANewCardAndKeptInDex() throws {
        for seed in 0..<30 as Range<UInt64> {
            let (before, after) = try migrate(LegacyFixtures.poyomon800, seed: seed)
            #expect(after.monster.stage == 0)
            #expect(after.monster.id == before.monster.id)
            #expect(after.monster.experience == before.monster.experience)
            let ids = after.dex.map(\.speciesId)
            #expect(ids.count == 3)
            #expect(Array(ids.prefix(2)) == ["digitama", "poyomon"])
            #expect(ids[2] == after.monster.speciesId)
            #expect(after.dex[1].firstMetSteps == 500)
        }
        var cards = Set<String>()
        for seed in 0..<300 as Range<UInt64> {
            let (_, after) = try migrate(LegacyFixtures.poyomon800, seed: seed)
            cards.insert(after.monster.cardId ?? "")
        }
        #expect(cards == Set(SpeciesCatalog.cards.map(\.id)))
    }

    @Test func poyomonAt16000ReachesStageTwo() throws {
        let (_, after) = try migrate(LegacyFixtures.poyomon1600)
        #expect(after.monster.stage == 2)
        #expect(after.dex.count == 5) // digitama, poyomon, stage 0, 1, 2
        #expect(after.dex.map(\.firstMetSteps) == [0, 500, 500, EvolutionCard.requiredSteps(stage: 1), EvolutionCard.requiredSteps(stage: 2)])
    }

    @Test func unknownSpeciesIsLeftAlone() throws {
        let (before, after) = try migrate(LegacyFixtures.unknown)
        #expect(after.monster == before.monster)
        #expect(after.dex.map(\.speciesId) == ["mystery"])
        #expect(after.snapshot.supersedes(nil))
    }

    @Test(arguments: [LegacyFixtures.egg, LegacyFixtures.botamon, LegacyFixtures.punimon,
                      LegacyFixtures.poyomon800, LegacyFixtures.unknown])
    func migrationIsIdempotent(json: String) throws {
        var (_, state) = try migrate(json)
        let once = state
        var counting = CountingGenerator(seed: 4)
        state.migrateToEvolutionCatalog(at: migratedAt.addingTimeInterval(60), using: &counting)
        #expect(state == once)
        #expect(counting.draws == 0)
    }

    @Test func migratedStateSurvivesSaveAndLoad() throws {
        let (_, after) = try migrate(LegacyFixtures.poyomon1600)
        let restored = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(after))
        #expect(restored == after)
    }

    @Test(arguments: [0, 499, 500, 4_500])
    func legacyStarterChainsIntoCatalog(steps: Int) throws {
        var state = GameState(speciesId: "starter_acorn", name: "도토롱", now: LegacyFixtures.createdAt, timeZone: .gmt)
        state.enroll(at: LegacyFixtures.createdAt)
        var generator = SeededGenerator(seed: 2)
        state.settle(day: LegacyFixtures.createdAt, steps: steps, distance: 100, using: &generator)
        state.migrateLegacyStarter(at: migratedAt, using: &generator)
        #expect(state.dex.first?.speciesId == "digitama")
        #expect(state.monster.isEgg == (steps < 500))
        if steps == 4_500 {
            #expect(state.monster.stage == 0)
            #expect(state.dex.count == 2)
        }
        let once = state
        state.migrateToEvolutionCatalog(at: migratedAt, using: &generator)
        #expect(state == once)
    }

    @Test func legacyStateBecomesPublishableOnlyAfterMigration() throws {
        for json in [LegacyFixtures.egg, LegacyFixtures.botamon, LegacyFixtures.punimon,
                     LegacyFixtures.poyomon800, LegacyFixtures.unknown] {
            let (before, after) = try migrate(json)
            #expect(!before.snapshot.supersedes(nil))
            #expect(after.snapshot.supersedes(nil))
        }
    }

    @Test func missingEggEntryIsBackfilledAtTheFront() throws {
        var (_, state) = try migrate(LegacyFixtures.botamon)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        json["dex"] = (json["dex"] as! [[String: Any]]).filter { $0["speciesId"] as? String != "digitama" }
        state = try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(!state.dex.contains { $0.speciesId == "digitama" })
        state.migrateToEvolutionCatalog(at: migratedAt)
        #expect(state.dex.first?.speciesId == "digitama")
        #expect(state.dex.first?.firstMetSteps == 0)
        let once = state
        state.migrateToEvolutionCatalog(at: migratedAt)
        #expect(state == once)
    }

    @Test func cardWithoutDexKeyIsDamagedNotLegacy() throws {
        var (_, state) = try migrate(LegacyFixtures.botamon)
        _ = state
        let data = try JSONEncoder().encode(state)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["dex"] != nil)
        json["dex"] = nil
        let withoutKey = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(GameState.self, from: withoutKey) }
        json["dex"] = NSNull()
        let withNull = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(GameState.self, from: withNull) }
        state = try JSONDecoder().decode(GameState.self, from: data)
        #expect(!state.dex.isEmpty)
    }

    @Test func invalidDexInSavedFileIsDamaged() throws {
        let (_, state) = try migrate(LegacyFixtures.botamon)
        let data = try JSONEncoder().encode(state)
        let base = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try #require(base["dex"] as? [[String: Any]])
        func decode(_ dex: [[String: Any]]) throws {
            var json = base
            json["dex"] = dex
            _ = try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: json))
        }
        try decode(entries)
        #expect(throws: DecodingError.self) { try decode(entries + [entries[0]]) }
        var blank = entries[0]; blank["speciesId"] = ""
        #expect(throws: DecodingError.self) { try decode(entries + [blank]) }
        var negative = entries[0]; negative["speciesId"] = "other"; negative["firstMetSteps"] = -1
        #expect(throws: DecodingError.self) { try decode(entries + [negative]) }
        // A file without any dex key is still a valid legacy file.
        _ = try LegacyFixtures.gameState(LegacyFixtures.egg)
    }

    @Test func cardWithEmptyDexIsDamaged() throws {
        let (_, state) = try migrate(LegacyFixtures.botamon)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        json["dex"] = [[String: Any]]()
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(GameState.self, from: data) }
    }
}
