import Foundation
import Testing
@testable import DigiWalkerCore

@Suite struct EvolutionTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var day2: Date { start.addingTimeInterval(86400) }

    private func enrolled() -> GameState {
        GameState.enrolledEgg(at: start)
    }

    private func settled(steps: Int, seed: UInt64) -> GameState {
        var state = enrolled()
        var generator = SeededGenerator(seed: seed)
        state.settle(day: start, steps: steps, distance: nil, at: start, using: &generator)
        return state
    }

    @Test(arguments: [
        (499, nil as Int?), (500, 0), (4_999, 0), (5_000, 1), (14_999, 1), (15_000, 2),
        (29_999, 2), (30_000, 3), (49_999, 3), (50_000, 4), (74_999, 4), (75_000, 5), (100_000, 5),
    ])
    func stageFollowsCreditedSteps(steps: Int, expected: Int?) {
        for seed in 0..<20 as Range<UInt64> {
            let state = settled(steps: steps, seed: seed)
            #expect(state.monster.stage == expected)
            #expect(state.monster.isEgg == (expected == nil))
            #expect((state.monster.cardId == nil) == (expected == nil))
        }
    }

    @Test func pathStaysInsideChosenCardAndNeverPicksJogressOnlySpecies() throws {
        for seed in 0..<1000 as Range<UInt64> {
            var state = enrolled()
            var generator = SeededGenerator(seed: seed)
            var visited: [String] = []
            for stage in 0...5 {
                state.settle(day: start, steps: EvolutionCard.requiredSteps(stage: stage), distance: nil, at: start, using: &generator)
                visited.append(state.monster.speciesId)
            }
            let card = try #require(state.monster.card)
            #expect(visited.count == 6)
            for (stage, speciesId) in visited.enumerated() {
                #expect(card.eligible(stage: stage).map(\.speciesId).contains(speciesId))
                #expect(card.slot(of: speciesId)?.randomEligible == true)
            }
            #expect(state.dex.map(\.speciesId) == [SpeciesCatalog.eggId] + visited)
        }
    }

    @Test func everyCardAndEligibleSpeciesIsReachable() throws {
        var cards = Set<String>()
        var reached = Set<String>()
        // Locked species need their item, so the partner starts out owning every unlock item (an earlier partner's
        // grants); the rest of the run is then fully decided by the seed.
        let owner = testPartnerId(900)
        var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(enrolled())) as? [String: Any])
        root["items"] = ["digicore", "digimental_fate", "x_antibody", "digicode"].enumerated().map {
            ["itemId": $0.element, "monsterId": owner.uuidString, "segment": $0.offset + 1, "grantedAt": 1.0]
        }
        let holder = try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: root))
        for seed in 0..<3000 as Range<UInt64> {
            var state = holder
            var generator = SeededGenerator(seed: seed)
            state.settle(day: start, steps: EvolutionCard.requiredSteps(stage: 5), distance: nil, at: start, using: &generator)
            cards.insert(state.monster.cardId ?? "")
            reached.formUnion(state.dex.map(\.speciesId))
        }
        #expect(cards == Set(SpeciesCatalog.cards.map(\.id)))
        let eligible = SpeciesCatalog.cards.flatMap { $0.stages.flatMap { $0 } }.filter(\.randomEligible)
        for slot in eligible { #expect(reached.contains(slot.speciesId), "\(slot.speciesId) never reached") }
        #expect(!reached.contains("omegamon"))
        #expect(!reached.contains("susanoomon"))
    }

    @Test(arguments: ["agu_ex", "gabu_ex"])
    func sharedAlgomonContinuesInsideTheOwnCard(cardId: String) throws {
        var checked = 0
        for seed in 0..<2000 as Range<UInt64> {
            var state = enrolled()
            var generator = SeededGenerator(seed: seed)
            state.settle(day: start, steps: EvolutionCard.requiredSteps(stage: 3), distance: nil, at: start, using: &generator)
            guard state.monster.speciesId == "algomon_adult", state.monster.cardId == cardId else { continue }
            state.settle(day: start, steps: EvolutionCard.requiredSteps(stage: 4), distance: nil, at: start, using: &generator)
            let card = try #require(SpeciesCatalog.card(id: cardId))
            #expect(card.eligible(stage: 4).map(\.speciesId).contains(state.monster.speciesId))
            #expect(state.monster.cardId == cardId)
            checked += 1
            if checked == 5 { break }
        }
        #expect(checked > 0)
    }

    @Test func hatchPicksEachOfElevenCardsRoughlyEvenly() {
        var counts: [String: Int] = [:]
        for seed in 0..<2200 as Range<UInt64> {
            let state = settled(steps: 500, seed: seed)
            counts[state.monster.cardId ?? "", default: 0] += 1
        }
        #expect(Set(counts.keys) == Set(SpeciesCatalog.cards.map(\.id)))
        // Expected 200 per card; a wide band only guards against a card being skipped or doubled.
        for (card, count) in counts { #expect((120...280).contains(count), "\(card) \(count)") }
    }

    @Test(arguments: [("wolf_ex", "wanyamon"), ("agu_ex", "koromon")])
    func sharedBotamonEvolvesInsideTheDrawnCard(cardId: String, nextSpecies: String) throws {
        var checked = 0
        for seed in 0..<2000 as Range<UInt64> {
            var state = enrolled()
            var generator = SeededGenerator(seed: seed)
            state.settle(day: start, steps: 500, distance: nil, at: start, using: &generator)
            guard state.monster.speciesId == "botamon", state.monster.cardId == cardId else { continue }
            state.settle(day: start, steps: EvolutionCard.requiredSteps(stage: 1), distance: nil, at: start, using: &generator)
            #expect(state.monster.speciesId == nextSpecies)
            state.settle(day: start, steps: EvolutionCard.requiredSteps(stage: 5), distance: nil, at: start, using: &generator)
            let card = try #require(SpeciesCatalog.card(id: cardId))
            #expect(state.monster.cardId == cardId)
            #expect(state.dex.dropFirst().allSatisfy { card.stage(of: $0.speciesId) != nil })
            checked += 1
            if checked == 5 { break }
        }
        #expect(checked > 0)
    }

    @Test func stageTwoWithTwoCandidatesStaysInsideThem() throws {
        let card = try #require(SpeciesCatalog.card(id: "agni_ex"))
        #expect(card.stages[2].map(\.speciesId) == ["flamon", "gottsumon"])
        var seen = Set<String>()
        for seed in 0..<2000 as Range<UInt64> {
            let state = settled(steps: EvolutionCard.requiredSteps(stage: 2), seed: seed)
            guard state.monster.cardId == "agni_ex" else { continue }
            #expect(state.monster.stage == 2)
            seen.insert(state.monster.speciesId)
        }
        #expect(seen == ["flamon", "gottsumon"])
    }

    @Test func jogressOnlySpeciesAreNeverReachedOnTheirOwnCards() {
        for seed in 0..<2000 as Range<UInt64> {
            let state = settled(steps: EvolutionCard.requiredSteps(stage: 5), seed: seed)
            guard ["agni_ex", "wolf_ex"].contains(state.monster.cardId) else { continue }
            #expect(state.monster.speciesId != "susanoomon")
        }
    }

    @Test func largeFirstReadingEvolvesStageByStageAndRecordsEverything() {
        let state = enrolled()
        var counting = CountingGenerator(seed: 7)
        var result = state
        let at = start.addingTimeInterval(600)
        result.settle(day: start, steps: EvolutionCard.requiredSteps(stage: 5) + 2_000, distance: nil, at: at, using: &counting)
        #expect(counting.draws == 7) // card + stage 0 + stages 1...5
        #expect(result.monster.stage == 5)
        #expect(result.dex.count == 7)
        #expect(result.dex.map(\.firstMetSteps) == [0] + (0...5).map(EvolutionCard.requiredSteps(stage:)))
        #expect(Set(result.dex.dropFirst().map(\.firstMetAt)) == [at])
        #expect(result.dex.first?.firstMetAt == start)
        #expect(result.dex.first?.speciesId == "digitama")
        #expect(result.dex.dropFirst().allSatisfy { $0.cardId == result.monster.cardId })
        #expect(result.monster.name == result.monster.species?.name)
    }

    @Test func daysAccumulateLikeBefore() {
        var state = enrolled()
        var generator = SeededGenerator(seed: 1)
        state.settle(day: start, steps: 4_000, distance: nil, using: &generator)
        #expect(state.monster.stage == 0)
        state.settle(day: day2, steps: 2_000, distance: nil, using: &generator)
        #expect(state.monster.totalCreditedSteps == 6_000)
        #expect(state.monster.stage == 1)
        #expect(state.monster.experience == 600)
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
        state.settle(day: start, steps: EvolutionCard.requiredSteps(stage: 5), distance: nil, at: start, using: &counting)
        let drawn = counting.draws
        let species = state.monster.speciesId
        state.settle(day: day2, steps: 200_000, distance: nil, at: day2, using: &counting)
        #expect(state.monster.speciesId == species)
        #expect(counting.draws == drawn)
    }

    @Test func evolutionKeepsIdentityLedgerAndXP() {
        var state = enrolled()
        var generator = SeededGenerator(seed: 5)
        state.settle(day: start, steps: 4_999, distance: 800, at: start, using: &generator)
        let before = state
        state.settle(day: day2, steps: 46_000, distance: 1000, at: day2, using: &generator)
        #expect(state.monster.id == before.monster.id)
        #expect(state.monster.stage == 4)
        for (key, ledger) in before.ledgers { #expect(state.ledgers[key] == ledger) }
        #expect(state.ledgers.count == 2)
        #expect(state.monster.experience == 490 + 4_600)
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
