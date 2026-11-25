import Foundation
import Testing
@testable import DigiWalkerCore

@Suite struct EvolutionTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var day2: Date { start.addingTimeInterval(86400) }

    private func enrolled() -> GameState {
        var state = GameState(now: start, timeZone: .gmt)
        state.enroll(at: start)
        return state
    }

    private func settled(steps: Int, seed: UInt64) -> GameState {
        var state = enrolled()
        var generator = SeededGenerator(seed: seed)
        state.settle(day: start, steps: steps, distance: nil, at: start, using: &generator)
        return state
    }

    @Test(arguments: [
        (499, nil as Int?), (500, 0), (9_999, 0), (10_000, 1), (14_999, 1), (15_000, 2),
        (19_999, 2), (20_000, 3), (24_999, 3), (25_000, 4), (29_999, 4), (30_000, 5), (100_000, 5),
    ])
    func stageFollowsCreditedSteps(steps: Int, expected: Int?) {
        for seed in 0..<20 as Range<UInt64> {
            let state = settled(steps: steps, seed: seed)
            #expect(state.monster.stage == expected)
            #expect(state.monster.isEgg == (expected == nil))
            #expect((state.monster.cardId == nil) == (expected == nil))
        }
    }

    @Test func pathStaysInsideChosenCardAndNeverPicksOmegamon() throws {
        for seed in 0..<300 as Range<UInt64> {
            var state = enrolled()
            var generator = SeededGenerator(seed: seed)
            var visited: [String] = []
            for steps in stride(from: 5_000, through: 30_000, by: 5_000) {
                state.settle(day: start, steps: steps, distance: nil, at: start, using: &generator)
                visited.append(state.monster.speciesId)
            }
            let card = try #require(state.monster.card)
            #expect(visited.count == 6)
            for (stage, speciesId) in visited.enumerated() {
                #expect(card.eligible(stage: stage).map(\.speciesId).contains(speciesId))
                #expect(speciesId != "omegamon")
            }
            #expect(state.dex.map(\.speciesId) == [SpeciesCatalog.eggId] + visited)
        }
    }

    @Test func everyCardAndEligibleSpeciesIsReachable() {
        var cards = Set<String>()
        var reached = Set<String>()
        for seed in 0..<600 as Range<UInt64> {
            let state = settled(steps: 30_000, seed: seed)
            cards.insert(state.monster.cardId ?? "")
            reached.formUnion(state.dex.map(\.speciesId))
        }
        #expect(cards == ["agu_ex", "gabu_ex", "guil_ex"])
        let eligible = SpeciesCatalog.cards.flatMap { $0.stages.flatMap { $0 } }.filter(\.randomEligible)
        for slot in eligible { #expect(reached.contains(slot.speciesId), "\(slot.speciesId) never reached") }
        #expect(!reached.contains("omegamon"))
    }

    @Test(arguments: ["agu_ex", "gabu_ex"])
    func sharedAlgomonContinuesInsideTheOwnCard(cardId: String) throws {
        var checked = 0
        for seed in 0..<2000 as Range<UInt64> {
            var state = enrolled()
            var generator = SeededGenerator(seed: seed)
            state.settle(day: start, steps: 20_000, distance: nil, at: start, using: &generator)
            guard state.monster.speciesId == "algomon_adult", state.monster.cardId == cardId else { continue }
            state.settle(day: start, steps: 25_000, distance: nil, at: start, using: &generator)
            let card = try #require(SpeciesCatalog.card(id: cardId))
            #expect(card.eligible(stage: 4).map(\.speciesId).contains(state.monster.speciesId))
            #expect(state.monster.cardId == cardId)
            checked += 1
            if checked == 5 { break }
        }
        #expect(checked > 0)
    }

    @Test func largeFirstReadingEvolvesStageByStageAndRecordsEverything() {
        let state = enrolled()
        var counting = CountingGenerator(seed: 7)
        var result = state
        let at = start.addingTimeInterval(600)
        result.settle(day: start, steps: 32_000, distance: nil, at: at, using: &counting)
        #expect(counting.draws == 7) // card + stage 0 + stages 1...5
        #expect(result.monster.stage == 5)
        #expect(result.dex.count == 7)
        #expect(result.dex.map(\.firstMetSteps) == [0, 500, 10_000, 15_000, 20_000, 25_000, 30_000])
        #expect(Set(result.dex.dropFirst().map(\.firstMetAt)) == [at])
        #expect(result.dex.first?.firstMetAt == start)
        #expect(result.dex.first?.speciesId == "digitama")
        #expect(result.dex.dropFirst().allSatisfy { $0.cardId == result.monster.cardId })
        #expect(result.monster.name == result.monster.species?.name)
    }

    @Test func daysAccumulateLikeBefore() {
        var state = enrolled()
        var generator = SeededGenerator(seed: 1)
        state.settle(day: start, steps: 7_000, distance: nil, using: &generator)
        #expect(state.monster.stage == 0)
        state.settle(day: day2, steps: 4_000, distance: nil, using: &generator)
        #expect(state.monster.totalCreditedSteps == 11_000)
        #expect(state.monster.stage == 1)
        #expect(state.monster.experience == 1_100)
    }

    @Test func replayAndLowerReadingsChangeNothingAndDrawNothing() {
        var state = enrolled()
        var counting = CountingGenerator(seed: 3)
        state.settle(day: start, steps: 12_000, distance: 500, at: start, using: &counting)
        let drawn = counting.draws
        let snapshot = state
        state.settle(day: start, steps: 12_000, distance: 500, at: start, using: &counting)
        state.settle(day: start, steps: 8_000, distance: 100, at: start, using: &counting)
        state.settle(day: start, steps: nil, distance: nil, at: start, using: &counting)
        #expect(state == snapshot)
        #expect(counting.draws == drawn)
    }

    @Test func stoppingAtStageFiveNeverDrawsAgain() {
        var state = enrolled()
        var counting = CountingGenerator(seed: 9)
        state.settle(day: start, steps: 30_000, distance: nil, at: start, using: &counting)
        let drawn = counting.draws
        let species = state.monster.speciesId
        state.settle(day: day2, steps: 100_000, distance: nil, at: day2, using: &counting)
        #expect(state.monster.speciesId == species)
        #expect(counting.draws == drawn)
    }

    @Test func evolutionKeepsIdentityLedgerAndXP() {
        var state = enrolled()
        var generator = SeededGenerator(seed: 5)
        state.settle(day: start, steps: 4_999, distance: 800, at: start, using: &generator)
        let before = state
        state.settle(day: day2, steps: 21_000, distance: 1000, at: day2, using: &generator)
        #expect(state.monster.id == before.monster.id)
        #expect(state.monster.stage == 4)
        for (key, ledger) in before.ledgers { #expect(state.ledgers[key] == ledger) }
        #expect(state.ledgers.count == 2)
        #expect(state.monster.experience == 490 + 2_100)
        #expect(state.monster.distanceMeters == 1000 + 800)
        #expect(state.revision == before.revision + 1)
    }

    @Test func stateRoundTripsThroughJSONAndResumes() throws {
        var state = settled(steps: 16_000, seed: 11)
        state.recordObservation(steps: 16_000, at: start)
        var restored = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(state))
        #expect(restored == state)
        var generator = SeededGenerator(seed: 99)
        restored.settle(day: start, steps: 16_000, distance: nil, at: start, using: &generator)
        #expect(restored == state)
    }
}
