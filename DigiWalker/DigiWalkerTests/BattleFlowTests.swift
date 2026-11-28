import DigiWalkerCore
import Foundation
import Testing
@testable import DigiWalker

@MainActor
struct BattleFlowTests {
    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private func snapshot(species: String, card: String?, dex: [String]) throws -> MonsterSnapshot {
        let name = SpeciesCatalog.info(id: species)?.name ?? species
        let cardPart = card.map { #","cardId":"\#($0)""# } ?? ""
        let dexPart = dex.map { #"{"speciesId":"\#($0)","firstMetAt":821692800,"firstMetSteps":0}"# }.joined(separator: ",")
        let json = #"{"schemaVersion":2,"revision":1,"createdAt":821692800,"monster":{"id":"7770E692-324B-4A27-90EA-437743B4195A","speciesId":"\#(species)","name":"\#(name)","totalCreditedSteps":0,"distanceMeters":0\#(cardPart)},"timeZone":{"identifier":"GMT"},"dex":[\#(dexPart)]}"#
        return try JSONDecoder().decode(MonsterSnapshot.self, from: Data(json.utf8))
    }

    private func flow(current: String = "koromon", dex: [String] = ["digitama", "botamon", "koromon", "agumon", "gabumon"],
                      seed: UInt64 = 1) throws -> BattleFlow {
        BattleFlow(snapshot: try snapshot(species: current, card: current == "digitama" ? nil : "agu_ex", dex: dex), rng: Seeded(state: seed))
    }

    private func qr(_ id: String) -> String { BattleCard(speciesId: id, name: SpeciesCatalog.info(id: id)!.name)!.encoded() }

    @Test func errorMessages() throws {
        let f = try flow()
        let cases: [(String, String)] = [
            ("https://example.com", "DigiWalker 배틀 QR이 아니에요"),
            (String(repeating: "x", count: 600), "DigiWalker 배틀 QR이 아니에요"),
            ("digiwalker-battle:1?s=agumon", "DigiWalker 배틀 QR이 아니에요"),
            ("digiwalker-battle:2?s=agumon&t=2&n=a", "앱 버전이 달라요. 두 기기 모두 앱을 최신으로 설치해 주세요"),
            ("digiwalker-battle:1?s=nope&t=2&n=a", "이 기기에서 모르는 디지몬이에요. 앱을 최신으로 설치해 주세요"),
            ("digiwalker-battle:1?s=digitama&t=0&n=a", "알은 배틀할 수 없어요"),
            ("digiwalker-battle:1?s=agumon&t=3&n=a", "배틀할 수 없는 디지몬 정보예요"),
            ("digiwalker-battle:1?s=poyomon&t=0&n=a", "배틀할 수 없는 디지몬 정보예요"),
        ]
        for (text, message) in cases {
            f.handleScanned(text)
            #expect(f.notice == message, "\(text)")
            #expect(f.encounter == nil && f.pendingPick == nil)
        }
    }

    @Test func sameStageStartsTheBattle() throws {
        let f = try flow(current: "agumon")
        f.handleScanned(qr("gabumon"))
        #expect(f.notice == nil)
        #expect(f.encounter?.mine.speciesId == "agumon")
        #expect(f.encounter?.opponent.speciesId == "gabumon")
        #expect(f.encounter?.session.rounds.isEmpty == true)
    }

    @Test func lowerStageAsksToPickFromTheSameStage() throws {
        let f = try flow(current: "koromon")
        f.handleScanned(qr("agumon"))
        let pick = try #require(f.pendingPick)
        #expect(pick.stage == 2)
        #expect(pick.candidates.map(\.speciesId) == ["agumon", "gabumon"])
        #expect(f.encounter == nil)
        // Picking fights with that one; the selected fighter on the screen is unchanged.
        f.startBattle(mine: pick.candidates[1], opponent: pick.opponent)
        #expect(f.encounter?.mine.speciesId == "gabumon")
        #expect(f.pendingPick == nil)
        #expect(f.myFighter?.speciesId == "koromon")
    }

    @Test func noSameStageAndOpponentMustLower() throws {
        let f = try flow(current: "koromon", dex: ["digitama", "koromon"])
        f.handleScanned(qr("agumon"))
        #expect(f.notice == "같은 단계의 디지몬이 없어요")
        let g = try flow(current: "agumon")
        g.handleScanned(qr("koromon"))
        #expect(g.notice == "상대가 같은 단계의 디지몬으로 QR을 다시 만들어야 해요")
        #expect(g.encounter == nil && g.pendingPick == nil)
    }

    @Test func eggBlocksTheWholeScreen() throws {
        let f = try flow(current: "digitama", dex: ["digitama", "botamon", "agumon"])
        #expect(f.blockedMessage == "부화한 뒤에 배틀할 수 있어요")
        #expect(f.myCard == nil)
        f.handleScanned(qr("agumon"))
        #expect(f.notice == "부화한 뒤에 배틀할 수 있어요")
        #expect(f.encounter == nil && f.pendingPick == nil)
    }

    @Test func myCardFollowsTheSelectedFighter() throws {
        let f = try flow(current: "agumon")
        #expect(f.myCard?.speciesId == "agumon")
        f.select(BattleFighter(speciesId: "gabumon", name: "파피몬", stage: 2))
        #expect(f.myCard?.speciesId == "gabumon")
        f.select(BattleFighter(speciesId: "greymon", name: "그레이몬", stage: 3)) // not in the roster: ignored
        #expect(f.myFighter?.speciesId == "gabumon")
    }

    @Test func playingToTheEndAndRematch() throws {
        let f = try flow(current: "agumon")
        f.handleScanned(qr("gabumon"))
        let first = try #require(f.encounter)
        var guardCount = 0
        while f.encounter?.session.isFinished == false, guardCount < 50 { f.choose(.attack); guardCount += 1 }
        let done = try #require(f.encounter?.session)
        #expect(done.isFinished && (2...3).contains(done.rounds.count) || done.rounds.count > 3)
        #expect(done.winner != nil)
        f.choose(.attack)
        #expect(f.encounter?.session.rounds.count == done.rounds.count) // ignored once finished
        f.rematch()
        let again = try #require(f.encounter)
        #expect(again.mine == first.mine && again.opponent == first.opponent)
        #expect(again.session.rounds.isEmpty)
        #expect(again.session.opponent != first.session.opponent)
    }

    @Test func extraRoundIsReachedWhenGuardsDraw() throws {
        let f = try flow(current: "agumon")
        f.handleScanned(qr("gabumon"))
        let all = [BattleMove(.defend, 1), BattleMove(.defend, 2), BattleMove(.defend, 3)]
        var e = try #require(f.encounter)
        e.session = BattleSession(opponent: all)!
        f.encounter = e
        for _ in 0..<3 { f.choose(.defend) }
        #expect(f.encounter?.session.isAwaitingExtraRound == true)
        #expect(BattleFlow.score(f.encounter!.session) == "0승 0패 3무")
    }

    @Test func summaryText() {
        func first(_ mine: BattleMove, _ theirs: BattleMove) -> BattleSession.Round {
            var s = BattleSession(opponent: [theirs, theirs, theirs])!
            s.play(mine)
            return s.rounds[0]
        }
        let atk = { BattleMove(.attack, $0) }, def = { BattleMove(.defend, $0) }
        #expect(BattleFlow.summary(first(atk(70), def(30))) == "1판 크리티컬! 승")
        #expect(BattleFlow.summary(first(def(10), def(50))) == "1판 무승부")
        #expect(BattleFlow.summary(first(atk(10), def(90))) == "1판 반격… 패")
        #expect(BattleFlow.summary(first(def(90), atk(10))) == "1판 반격! 승")
        #expect(BattleFlow.summary(first(def(10), atk(90))) == "1판 크리티컬… 패")
        #expect(BattleFlow.summary(first(atk(90), atk(10))) == "1판 승")
        #expect(BattleFlow.summary(first(atk(10), atk(90))) == "1판 패")
        #expect(BattleFlow.detail(first(atk(32), def(55))) == "나 공격 32 · 상대 방어 55")
        // Round numbers follow the order played.
        var s = BattleSession(opponent: [def(30), def(50), def(90)])!
        s.play(atk(70)); s.play(def(10)); s.play(atk(10))
        #expect(s.rounds.map(BattleFlow.summary) == ["1판 크리티컬! 승", "2판 무승부", "3판 반격… 패"])
    }

    // MARK: Cache updates

    @Test func updateToAnEggBlocksAndHatchingUnblocks() throws {
        let dex = ["digitama", "botamon", "koromon", "agumon", "gabumon"]
        let f = try flow(current: "agumon", dex: dex)
        #expect(f.blockedMessage == nil)
        f.update(snapshot: try snapshot(species: "digitama", card: nil, dex: ["digitama"] + dex.dropFirst()))
        #expect(f.blockedMessage == "부화한 뒤에 배틀할 수 있어요")
        #expect(f.myCard == nil) // blocked: no QR even though the dex still has fighters
        f.handleScanned(qr("gabumon"))
        #expect(f.notice == "부화한 뒤에 배틀할 수 있어요")
        #expect(f.encounter == nil)
        f.update(snapshot: try snapshot(species: "botamon", card: "agu_ex", dex: dex))
        #expect(f.blockedMessage == nil)
        #expect(f.myCard != nil)
        f.handleScanned(qr("botamon"))
        #expect(f.encounter != nil)
    }

    @Test func updateKeepsAnOwnedChoiceAndResetsAMissingOne() throws {
        let dex = ["digitama", "koromon", "agumon", "gabumon"]
        let f = try flow(current: "agumon", dex: dex)
        f.select(BattleFighter(speciesId: "gabumon", name: "파피몬", stage: 2))
        f.update(snapshot: try snapshot(species: "agumon", card: "agu_ex", dex: dex + ["greymon"]))
        #expect(f.myFighter?.speciesId == "gabumon")
        f.update(snapshot: try snapshot(species: "koromon", card: "agu_ex", dex: ["digitama", "koromon", "agumon"]))
        #expect(f.myFighter?.speciesId == "koromon")
    }

    @Test func updateDoesNotTouchABattleInProgress() throws {
        let f = try flow(current: "agumon")
        f.handleScanned(qr("gabumon"))
        f.choose(.attack)
        let before = f.encounter
        f.update(snapshot: try snapshot(species: "digitama", card: nil, dex: ["digitama"]))
        #expect(f.encounter == before)
    }

    // MARK: Three picks before any result

    private func rigged(_ f: BattleFlow, _ pattern: [BattleMove]) throws {
        var e = try #require(f.encounter)
        e.session = BattleSession(opponent: pattern)!
        f.encounter = e
    }

    @Test func nothingIsJudgedBeforeTheThirdPick() throws {
        let f = try flow(current: "agumon")
        f.handleScanned(qr("gabumon"))
        // Opponent always defends with 0: any attack of mine wins every round (2:0 after two rounds).
        try rigged(f, [BattleMove(.defend, 0), BattleMove(.defend, 0), BattleMove(.defend, 0)])
        f.choose(.attack); f.choose(.attack)
        var e = try #require(f.encounter)
        #expect(e.isCollecting && !e.isFinished && e.session.rounds.isEmpty && e.picks.count == 2)
        f.choose(.attack)
        e = try #require(f.encounter)
        #expect(!e.isCollecting && e.isFinished && e.session.winner == .me)
    }

    @Test func thirdPickAfterTwoZeroIsShownButNotJudged() throws {
        let f = try flow(current: "agumon")
        f.handleScanned(qr("gabumon"))
        try rigged(f, [BattleMove(.defend, 0), BattleMove(.defend, 0), BattleMove(.attack, 100)])
        f.choose(.attack); f.choose(.attack); f.choose(.defend)
        let e = try #require(f.encounter)
        #expect(e.session.rounds.count == 2 && e.session.myWins == 2 && e.session.theirWins == 0)
        #expect(e.picks.count == 3)
        let undecided = e.undecidedPicks
        #expect(undecided.count == 1 && undecided[0].index == 2 && undecided[0].move.action == .defend)
        #expect(BattleFlow.undecidedSummary(index: 2) == "3판 — (승부 결정 후)")
        #expect(BattleFlow.undecidedDetail(BattleMove(.defend, 42)) == "나 방어 42")
        f.choose(.attack) // finished: ignored
        #expect(f.encounter == e)
    }

    @Test func undecidedAfterThreeRoundsContinuesOneByOne() throws {
        let f = try flow(current: "agumon")
        f.handleScanned(qr("gabumon"))
        try rigged(f, [BattleMove(.defend, 1), BattleMove(.defend, 2), BattleMove(.defend, 3)])
        for _ in 0..<3 { f.choose(.defend) }
        var e = try #require(f.encounter)
        #expect(e.isAwaitingExtraRound && e.undecidedPicks.isEmpty)
        f.choose(.defend)
        e = try #require(f.encounter)
        #expect(e.session.rounds.count == 4 && e.picks.count == 3)
    }

    @Test func rematchWhileBlockedReturnsToTheLobby() throws {
        let f = try flow(current: "agumon")
        f.handleScanned(qr("gabumon"))
        #expect(f.encounter != nil)
        f.update(snapshot: try snapshot(species: "digitama", card: nil, dex: ["digitama", "agumon", "gabumon"]))
        #expect(f.encounter != nil) // an ongoing battle is not touched by the update
        f.rematch()
        #expect(f.encounter == nil)
        #expect(f.blockedMessage != nil)
    }

    @Test func rematchWithoutTheFighterInTheRosterEndsTheBattle() throws {
        let f = try flow(current: "agumon", dex: ["digitama", "agumon", "gabumon"])
        f.handleScanned(qr("gabumon"))
        f.update(snapshot: try snapshot(species: "koromon", card: "agu_ex", dex: ["digitama", "koromon", "gabumon"]))
        f.rematch()
        #expect(f.encounter == nil)
    }

    @Test func automaticFighterFollowsEvolution() throws {
        let dex = ["digitama", "koromon", "agumon", "greymon"]
        let f = try flow(current: "agumon", dex: dex)
        #expect(f.myFighter?.speciesId == "agumon" && !f.isFighterChosenByUser)
        f.update(snapshot: try snapshot(species: "greymon", card: "agu_ex", dex: dex))
        #expect(f.myFighter?.speciesId == "greymon")
        #expect(f.myCard?.speciesId == "greymon")
        f.handleScanned(qr("greymon"))
        #expect(f.encounter?.mine.speciesId == "greymon")
    }

    @Test func chosenFighterSurvivesEvolution() throws {
        let dex = ["digitama", "koromon", "agumon", "gabumon", "greymon"]
        let f = try flow(current: "agumon", dex: dex)
        f.select(BattleFighter(speciesId: "gabumon", name: "파피몬", stage: 2))
        f.update(snapshot: try snapshot(species: "greymon", card: "agu_ex", dex: dex))
        #expect(f.myFighter?.speciesId == "gabumon" && f.isFighterChosenByUser)
    }
}
