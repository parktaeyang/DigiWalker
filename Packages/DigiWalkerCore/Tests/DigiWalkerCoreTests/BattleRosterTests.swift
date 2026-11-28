import Foundation
import Testing
@testable import DigiWalkerCore

struct BattleRosterTests {
    private func snapshot(species: String, name: String, card: String?, dex: [String]?, version: Int = 2) throws -> MonsterSnapshot {
        let cardPart = card.map { #","cardId":"\#($0)""# } ?? ""
        let dexPart = dex.map {
            #","dex":["# + $0.map { #"{"speciesId":"\#($0)","firstMetAt":821692800,"firstMetSteps":0}"# }.joined(separator: ",") + "]"
        } ?? ""
        let json = #"{"schemaVersion":\#(version),"revision":1,"createdAt":821692800,"monster":{"id":"7770E692-324B-4A27-90EA-437743B4195A","speciesId":"\#(species)","name":"\#(name)","totalCreditedSteps":0,"distanceMeters":0\#(cardPart)},"timeZone":{"identifier":"GMT"}\#(dexPart)}"#
        return try JSONDecoder().decode(MonsterSnapshot.self, from: Data(json.utf8))
    }

    private func roster(current: String = "agumon", card: String? = "agu_ex", dex: [String]?, version: Int = 2) throws -> BattleRoster {
        let name = SpeciesCatalog.info(id: current)?.name ?? current
        return BattleRoster(snapshot: try snapshot(species: current, name: name, card: card, dex: dex, version: version))
    }

    private func opponent(_ id: String) -> BattleCard { BattleCard(speciesId: id, name: SpeciesCatalog.info(id: id)!.name)! }

    private func ids(_ f: [BattleFighter]) -> [String] { f.map(\.speciesId) }

    @Test func candidatesByStageExcludeEggLegacyAndUnknown() throws {
        let r = try roster(dex: ["digitama", "poyomon", "mystery", "botamon", "koromon", "agumon", "punimon", "gabumon"])
        #expect(r.stages == [0, 1, 2])
        #expect(ids(r.candidates(stage: 0)) == ["botamon", "punimon"])
        #expect(ids(r.candidates(stage: 1)) == ["koromon"])
        #expect(ids(r.candidates(stage: 2)) == ["agumon", "gabumon"])
        #expect(r.candidates(stage: 3).isEmpty)
        #expect(r.candidates(stage: 0).first?.name == "깜몬")
    }

    @Test func orderFollowsDiscoveryListNotDexOrder() throws {
        let r = try roster(dex: ["digitama", "gabumon", "agumon", "botamon", "punimon"])
        #expect(ids(r.candidates(stage: 2)) == ["agumon", "gabumon"])
        #expect(ids(r.candidates(stage: 0)) == ["botamon", "punimon"])
    }

    @Test func sharedSpeciesAppearOnce() throws {
        let r = try roster(current: "wargreymon", card: "agu_ex", dex: ["digitama", "omegamon", "wargreymon"])
        let stage5 = ids(r.candidates(stage: 5))
        #expect(stage5.filter { $0 == "omegamon" }.count == 1)
        #expect(Set(stage5) == ["omegamon", "wargreymon"])
    }

    @Test func currentPartnerIsTheDefault() throws {
        let r = try roster(dex: ["digitama", "botamon", "agumon"])
        #expect(r.defaultFighter == BattleFighter(speciesId: "agumon", name: "아구몬", stage: 2))
        #expect(!r.isBlockedByEgg)
    }

    @Test func eggPartnerBlocksEverything() throws {
        let r = try roster(current: "digitama", card: nil, dex: ["digitama", "botamon", "agumon"])
        #expect(r.isBlockedByEgg)
        #expect(r.defaultFighter == nil)
        // Even a ready-looking match is blocked, with or without a fighter picked.
        let mine = r.candidates(stage: 2).first
        #expect(BattleMatch.match(mine: mine, opponent: opponent("agumon"), roster: r) == .eggBlocked)
        #expect(BattleMatch.match(mine: nil, opponent: opponent("botamon"), roster: r) == .eggBlocked)
        #expect(BattleMatch.match(mine: nil, opponent: opponent("greymon"), roster: r) == .eggBlocked)
    }

    @Test func legacyPoyomonPartnerHasNoDefaultButIsNotBlocked() throws {
        let r = try roster(current: "poyomon", card: nil, dex: ["digitama", "poyomon", "botamon"])
        #expect(!r.isBlockedByEgg)
        #expect(r.defaultFighter == nil)
        #expect(ids(r.candidates(stage: 0)) == ["botamon"])
    }

    @Test func v1CacheHasOnlyTheCurrentPartner() throws {
        let r = try roster(current: "agumon", card: "agu_ex", dex: nil, version: 1)
        #expect(r.stages == [2])
        #expect(ids(r.candidates(stage: 2)) == ["agumon"])
        #expect(r.defaultFighter?.speciesId == "agumon")
    }

    @Test func v1LegacyBotamonWithoutCardCountsAsStageZero() throws {
        let r = try roster(current: "botamon", card: nil, dex: nil, version: 1)
        #expect(r.defaultFighter == BattleFighter(speciesId: "botamon", name: "깜몬", stage: 0))
        #expect(ids(r.candidates(stage: 0)) == ["botamon"])
    }

    @Test func v1EggIsBlocked() throws {
        let r = try roster(current: "digitama", card: nil, dex: nil, version: 1)
        #expect(r.isBlockedByEgg && r.stages.isEmpty && r.defaultFighter == nil)
    }

    @Test func matchSameStageIsReady() throws {
        let r = try roster(dex: ["digitama", "agumon", "gabumon"])
        #expect(BattleMatch.match(mine: r.defaultFighter, opponent: opponent("gabumon"), roster: r)
            == .ready(r.defaultFighter!))
    }

    @Test func matchLowerPicksFromSameStage() throws {
        let r = try roster(current: "koromon", dex: ["digitama", "koromon", "agumon", "gabumon", "botamon", "greymon"])
        let m = BattleMatch.match(mine: r.defaultFighter, opponent: opponent("agumon"), roster: r)
        #expect(m == .pick(stage: 2, candidates: r.candidates(stage: 2)))
        #expect(ids(r.candidates(stage: 2)) == ["agumon", "gabumon"])
    }

    @Test func matchLowerWithoutSameStageFighter() throws {
        let r = try roster(current: "koromon", dex: ["digitama", "koromon", "botamon"])
        #expect(BattleMatch.match(mine: r.defaultFighter, opponent: opponent("agumon"), roster: r) == .noSameStage)
    }

    @Test func matchHigherAsksOpponentToLower() throws {
        let r = try roster(current: "greymon", dex: ["digitama", "greymon", "agumon"])
        #expect(BattleMatch.match(mine: r.defaultFighter, opponent: opponent("agumon"), roster: r) == .opponentMustLower)
    }

    @Test func matchWithoutFighterPicksOrHasNone() throws {
        let r = try roster(current: "poyomon", card: nil, dex: ["digitama", "poyomon", "botamon"])
        #expect(BattleMatch.match(mine: nil, opponent: opponent("punimon"), roster: r)
            == .pick(stage: 0, candidates: r.candidates(stage: 0)))
        #expect(BattleMatch.match(mine: nil, opponent: opponent("agumon"), roster: r) == .noSameStage)
    }

    @Test func fighterOutsideTheRosterIsTreatedAsNoChoice() throws {
        let r = try roster(current: "koromon", dex: ["digitama", "koromon", "agumon"])
        let stranger = BattleFighter(speciesId: "gabumon", name: "파피몬", stage: 2)
        #expect(!r.contains(stranger))
        #expect(BattleMatch.match(mine: stranger, opponent: opponent("agumon"), roster: r)
            == .pick(stage: 2, candidates: r.candidates(stage: 2)))
        #expect(BattleMatch.match(mine: stranger, opponent: opponent("greymon"), roster: r) == .noSameStage)
        // Higher than the opponent but not owned: no "opponent must lower" either.
        let high = BattleFighter(speciesId: "greymon", name: "그레이몬", stage: 3)
        #expect(BattleMatch.match(mine: high, opponent: opponent("agumon"), roster: r)
            == .pick(stage: 2, candidates: r.candidates(stage: 2)))
    }

    @Test func v4SnapshotWithItemsAndGeneration() throws {
        let json = #"{"schemaVersion":4,"revision":3,"createdAt":821692800,"generation":1,"items":[],"monster":{"id":"7770E692-324B-4A27-90EA-437743B4195A","speciesId":"greymon","name":"그레이몬","totalCreditedSteps":16000,"distanceMeters":0,"cardId":"agu_ex"},"timeZone":{"identifier":"GMT"},"dex":[{"speciesId":"digitama","firstMetAt":821692800,"firstMetSteps":0},{"speciesId":"agumon","firstMetAt":821692800,"firstMetSteps":500},{"speciesId":"greymon","firstMetAt":821692800,"firstMetSteps":5000}]}"#
        let snap = try JSONDecoder().decode(MonsterSnapshot.self, from: Data(json.utf8))
        let r = BattleRoster(snapshot: snap)
        #expect(r.defaultFighter == BattleFighter(speciesId: "greymon", name: "그레이몬", stage: 3))
        #expect(r.stages == [2, 3])
        #expect(!r.isBlockedByEgg)
    }
}
