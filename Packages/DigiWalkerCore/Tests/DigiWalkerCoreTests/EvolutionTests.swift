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
        (499, nil as Int?), (500, 0), (999, 0), (1000, 1), (1499, 1), (1500, 2),
        (1999, 2), (2000, 3), (2499, 3), (2500, 4), (2999, 4), (3000, 5), (10_000, 5),
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
            for steps in stride(from: 500, through: 3000, by: 500) {
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
            let state = settled(steps: 3000, seed: seed)
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
            state.settle(day: start, steps: 2000, distance: nil, at: start, using: &generator)
            guard state.monster.speciesId == "algomon_adult", state.monster.cardId == cardId else { continue }
            state.settle(day: start, steps: 2500, distance: nil, at: start, using: &generator)
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
        result.settle(day: start, steps: 3200, distance: nil, at: at, using: &counting)
        #expect(counting.draws == 7) // card + stage 0 + stages 1...5
        #expect(result.monster.stage == 5)
        #expect(result.dex.count == 7)
        #expect(result.dex.map(\.firstMetSteps) == [0, 500, 1000, 1500, 2000, 2500, 3000])
        #expect(Set(result.dex.dropFirst().map(\.firstMetAt)) == [at])
        #expect(result.dex.first?.firstMetAt == start)
        #expect(result.dex.first?.speciesId == "digitama")
        #expect(result.dex.dropFirst().allSatisfy { $0.cardId == result.monster.cardId })
        #expect(result.monster.name == result.monster.species?.name)
    }

    @Test func daysAccumulateLikeBefore() {
        var state = enrolled()
        var generator = SeededGenerator(seed: 1)
        state.settle(day: start, steps: 700, distance: nil, using: &generator)
        #expect(state.monster.stage == 0)
        state.settle(day: day2, steps: 400, distance: nil, using: &generator)
        #expect(state.monster.totalCreditedSteps == 1100)
        #expect(state.monster.stage == 1)
        #expect(state.monster.experience == 110)
    }

    @Test func replayAndLowerReadingsChangeNothingAndDrawNothing() {
        var state = enrolled()
        var counting = CountingGenerator(seed: 3)
        state.settle(day: start, steps: 1200, distance: 500, at: start, using: &counting)
        let drawn = counting.draws
        let snapshot = state
        state.settle(day: start, steps: 1200, distance: 500, at: start, using: &counting)
        state.settle(day: start, steps: 800, distance: 100, at: start, using: &counting)
        state.settle(day: start, steps: nil, distance: nil, at: start, using: &counting)
        #expect(state == snapshot)
        #expect(counting.draws == drawn)
    }

    @Test func stoppingAtStageFiveNeverDrawsAgain() {
        var state = enrolled()
        var counting = CountingGenerator(seed: 9)
        state.settle(day: start, steps: 3000, distance: nil, at: start, using: &counting)
        let drawn = counting.draws
        let species = state.monster.speciesId
        state.settle(day: day2, steps: 10_000, distance: nil, at: day2, using: &counting)
        #expect(state.monster.speciesId == species)
        #expect(counting.draws == drawn)
    }

    @Test func evolutionKeepsIdentityLedgerAndXP() {
        var state = enrolled()
        var generator = SeededGenerator(seed: 5)
        state.settle(day: start, steps: 499, distance: 800, at: start, using: &generator)
        let before = state
        state.settle(day: day2, steps: 2100, distance: 1000, at: day2, using: &generator)
        #expect(state.monster.id == before.monster.id)
        #expect(state.monster.stage == 4)
        for (key, ledger) in before.ledgers { #expect(state.ledgers[key] == ledger) }
        #expect(state.ledgers.count == 2)
        #expect(state.monster.experience == 40 + 210)
        #expect(state.monster.distanceMeters == 1000 + 800)
        #expect(state.revision == before.revision + 1)
    }

    @Test func stateRoundTripsThroughJSONAndResumes() throws {
        var state = settled(steps: 1600, seed: 11)
        state.recordObservation(steps: 1600, at: start)
        var restored = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(state))
        #expect(restored == state)
        var generator = SeededGenerator(seed: 99)
        restored.settle(day: start, steps: 1600, distance: nil, at: start, using: &generator)
        #expect(restored == state)
    }
}
