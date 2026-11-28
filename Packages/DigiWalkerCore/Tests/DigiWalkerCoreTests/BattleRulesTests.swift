import Foundation
import Testing
@testable import DigiWalkerCore

struct BattleRulesTests {
    private func atk(_ v: Int) -> BattleMove { BattleMove(.attack, v) }
    private func def(_ v: Int) -> BattleMove { BattleMove(.defend, v) }
    private func session(_ o: [BattleMove]) -> BattleSession { BattleSession(opponent: o)! }

    // MARK: judge

    @Test func attackVsAttack() {
        #expect(BattleRules.judge(mine: atk(60), theirs: atk(40)) == (.win, .clash))
        #expect(BattleRules.judge(mine: atk(40), theirs: atk(60)) == (.lose, .clash))
        #expect(BattleRules.judge(mine: atk(50), theirs: atk(50)) == (.win, .clash)) // tie: scanner wins
    }

    @Test func defendVsDefendAlwaysDraws() {
        #expect(BattleRules.judge(mine: def(90), theirs: def(10)) == (.draw, .guardDraw))
        #expect(BattleRules.judge(mine: def(10), theirs: def(90)) == (.draw, .guardDraw))
        #expect(BattleRules.judge(mine: def(30), theirs: def(30)) == (.draw, .guardDraw))
    }

    @Test func myAttackVsTheirDefend() {
        #expect(BattleRules.judge(mine: atk(70), theirs: def(30)) == (.win, .critical))
        #expect(BattleRules.judge(mine: atk(30), theirs: def(70)) == (.lose, .counter))
        #expect(BattleRules.judge(mine: atk(50), theirs: def(50)) == (.win, .critical))
    }

    @Test func myDefendVsTheirAttack() {
        #expect(BattleRules.judge(mine: def(70), theirs: atk(30)) == (.win, .counter))
        #expect(BattleRules.judge(mine: def(30), theirs: atk(70)) == (.lose, .critical))
        #expect(BattleRules.judge(mine: def(50), theirs: atk(50)) == (.win, .counter))
    }

    @Test func boundaryValues() {
        #expect(BattleRules.judge(mine: atk(0), theirs: atk(0)).outcome == .win)
        #expect(BattleRules.judge(mine: atk(100), theirs: atk(100)).outcome == .win)
        #expect(BattleRules.judge(mine: atk(100), theirs: atk(0)).outcome == .win)
        #expect(BattleRules.judge(mine: atk(0), theirs: atk(100)).outcome == .lose)
        #expect(BattleRules.judge(mine: atk(0), theirs: def(100)) == (.lose, .counter))
        #expect(BattleRules.judge(mine: def(0), theirs: atk(100)) == (.lose, .critical))
        #expect(BattleRules.judge(mine: def(0), theirs: atk(0)) == (.win, .counter))
        #expect(BattleMove(.attack, 150).value == 100)
        #expect(BattleMove(.defend, -5).value == 0)
    }

    @Test func everyCombination() {
        for ma in [BattleAction.attack, .defend] {
            for ta in [BattleAction.attack, .defend] {
                for mv in 0...100 {
                    for tv in 0...100 {
                        let r = BattleRules.judge(mine: BattleMove(ma, mv), theirs: BattleMove(ta, tv))
                        if ma == .defend && ta == .defend {
                            #expect(r.outcome == .draw && r.note == .guardDraw)
                        } else {
                            #expect(r.outcome != .draw, "\(ma)\(mv) vs \(ta)\(tv)")
                        }
                    }
                }
            }
        }
    }

    // MARK: session

    @Test func finishesAtTwoWinsAndIgnoresLaterPlays() {
        var s = session([atk(10), atk(10), atk(10)])
        let played1 = s.play(atk(50))
        #expect(played1)
        #expect(!s.isFinished)
        let played2 = s.play(atk(50))
        #expect(played2)
        #expect(s.isFinished && s.winner == .me && s.rounds.count == 2 && s.myWins == 2)
        let played3 = s.play(atk(99))
        #expect(!played3)
        #expect(s.rounds.count == 2)
        var rng = SeededGenerator(seed: 1)
        let played4 = s.play(.attack, using: &rng)
        #expect(!played4)
        #expect(s.rounds.count == 2)
    }

    @Test func opponentCanWinInTwo() {
        var s = session([atk(90), atk(90), atk(90)])
        s.play(atk(10)); s.play(atk(10))
        #expect(s.winner == .opponent && s.theirWins == 2 && s.rounds.count == 2)
    }

    @Test func extraRoundReusesPatternFromTheStart() {
        // Rounds: win, lose, draw -> 1:1 after three, round 4 uses opponent[0].
        var s = session([atk(10), atk(90), def(50)])
        s.play(atk(50)); s.play(atk(50)); s.play(def(50))
        #expect(s.myWins == 1 && s.theirWins == 1)
        #expect(s.isAwaitingExtraRound && !s.isFinished && s.winner == nil)
        #expect(s.nextOpponentMove == atk(10))
        s.play(atk(50))
        #expect(s.rounds[3].theirs == atk(10))
        #expect(s.isFinished && s.winner == .me && !s.isAwaitingExtraRound)
    }

    @Test func goesOnUntilTwoWinsWithPatternRepeating() {
        let pattern = [def(1), def(2), def(3)]
        var s = session(pattern)
        for _ in 0..<6 { s.play(def(50)) }
        #expect(s.rounds.map(\.theirs) == pattern + pattern)
        #expect(s.myWins == 0 && s.theirWins == 0 && s.isAwaitingExtraRound)
        s.play(def(50))
        #expect(s.rounds[6].theirs == pattern[0])
        #expect(s.rounds.map(\.index) == Array(0..<7))
    }

    @Test func guardOnlyNeverLoopsAndNeverEnds() {
        var s = session([def(10), def(20), def(30)])
        for _ in 0..<100 { s.play(def(100)) }
        #expect(s.rounds.count == 100)
        #expect(!s.isFinished && s.isAwaitingExtraRound)
        #expect(s.rounds.allSatisfy { $0.outcome == .draw })
        #expect(s.nextOpponentMove == s.opponent[100 % 3])
        // One attack always settles that round.
        s.play(atk(0))
        #expect(s.rounds.last?.outcome != .draw)
    }

    @Test func opponentPatternMustHaveThreeMoves() {
        #expect(BattleSession(opponent: []) == nil)
        #expect(BattleSession(opponent: [atk(1), atk(2)]) == nil)
        #expect(BattleSession(opponent: [atk(1), atk(2), atk(3), atk(4)]) == nil)
    }

    // MARK: randomness

    @Test func randomPatternShapeAndDeterminism() {
        var a = SeededGenerator(seed: 42), b = SeededGenerator(seed: 42)
        let p = BattleRules.randomPattern(using: &a)
        #expect(p.count == 3)
        #expect(p.allSatisfy { BattleMove.valueRange.contains($0.value) })
        #expect(p == BattleRules.randomPattern(using: &b))
        var seen = Set<BattleAction>()
        var g = SeededGenerator(seed: 7)
        for _ in 0..<200 {
            for m in BattleRules.randomPattern(using: &g) {
                #expect(BattleMove.valueRange.contains(m.value))
                seen.insert(m.action)
            }
        }
        #expect(seen == [.attack, .defend])
    }

    @Test func sessionFromRngUsesPatternOfThree() {
        var g = CountingGenerator(seed: 3)
        let s = BattleSession(using: &g)
        #expect(s.opponent.count == 3)
        #expect(g.draws > 0)
    }

    @Test func playingAnActionDrawsItsValueFromTheGenerator() {
        var s = session([def(0), def(0), def(0)])
        var g = CountingGenerator(seed: 9)
        let played5 = s.play(.attack, using: &g)
        #expect(played5)
        #expect(g.draws > 0)
        #expect(BattleMove.valueRange.contains(s.rounds[0].mine.value))
        #expect(s.rounds[0].mine.action == .attack)
        var again = SeededGenerator(seed: 9)
        var s2 = session([def(0), def(0), def(0)])
        s2.play(.attack, using: &again)
        #expect(s2.rounds[0].mine == s.rounds[0].mine)
    }

    @Test func randomValueReachesBothEnds() {
        var g = SeededGenerator(seed: 2024)
        let values = (0..<20_000).map { _ in BattleRules.randomValue(using: &g) }
        #expect(values.min() == 0)
        #expect(values.max() == 100)
    }
}
