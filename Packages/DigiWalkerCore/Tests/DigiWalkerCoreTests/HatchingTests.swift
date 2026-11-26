import Foundation
import Testing
@testable import DigiWalkerCore

@Suite struct HatchingTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func hatchesExactlyAt500AcrossDaysAndSurvivesReplay() throws {
        var state = GameState.fixedEgg(now: start)
        let eggID = state.monster.id
        state.enroll(at: start)
        state.recordObservation(steps: 9000, at: start)
        state.settle(day: start, steps: 499, distance: 700)
        state.settle(day: start, steps: 475, distance: 900)
        let tomorrow = start.addingTimeInterval(86400)
        state.settle(day: tomorrow, steps: 0, distance: nil)
        #expect(state.monster.isEgg)
        #expect(state.monster.totalCreditedSteps == 499)
        let before = state.snapshot
        state.settle(day: tomorrow, steps: 1, distance: nil)
        let baby = try #require(state.monster.species)
        #expect(state.monster.stage == 0)
        #expect(state.monster.name == baby.name)
        #expect(state.monster.totalCreditedSteps == 500)
        #expect(state.monster.id == eggID)
        #expect(state.monster.experience == 40) // Daily thresholds: 499 and 1.
        #expect(state.snapshot.supersedes(before))
        var restored = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(state))
        restored.settle(day: tomorrow, steps: 1, distance: nil)
        #expect(restored == state)
        // Total is 499 + 50,000 = 50,499: stage 4, so digitama + stages 0...4 = 6 entries.
        restored.settle(day: tomorrow, steps: 50_000, distance: nil)
        #expect(restored.monster.totalCreditedSteps == 50_499)
        #expect(restored.monster.stage == 4)
        #expect(restored.monster.cardId == state.monster.cardId)
        #expect(restored.dex.count == 6)
        #expect(restored.dex.first?.speciesId == "digitama")
        #expect(restored.dex.map(\.firstMetSteps) == [0] + (0...4).map(EvolutionCard.requiredSteps(stage:)))
        #expect(restored.dex.last?.speciesId == restored.monster.speciesId)
    }

    @Test func firstLargeReadingHatchesImmediately() throws {
        var state = GameState.fixedEgg(now: start)
        state.enroll(at: start)
        state.settle(day: start, steps: 4_030, distance: nil)
        #expect(state.monster.stage == 0) // 4,030 steps: stage 0 (500...4,999)
        #expect(state.dex.count == 2)
        #expect(state.dex.map(\.firstMetSteps) == [0, 500])
        #expect(state.dex.first?.speciesId == "digitama")
        #expect(state.dex.last?.speciesId == state.monster.speciesId)
        #expect(state.monster.totalCreditedSteps == 4_030)
        #expect(state.monster.experience == 400)
    }

    @Test(arguments: [0, 499, 500, 4_500]) func migrateSavedStarter(steps: Int) throws {
        var state = GameState(speciesId: "starter_acorn", name: "도토롱", now: start, timeZone: .gmt)
        state.enroll(at: start)
        state.settle(day: start, steps: steps, distance: 100)
        let original = state
        state.migrateLegacyStarter()
        #expect(state.monster.id == original.monster.id)
        #expect(state.monster.totalCreditedSteps == steps)
        #expect(state.monster.experience == original.monster.experience)
        #expect(state.ledgers == original.ledgers)
        #expect(state.snapshot.supersedes(original.snapshot))
        #expect(state.monster.isEgg == (steps < 500))
        #expect((state.monster.stage != nil) == (steps >= 500))
        let migrated = state
        state.migrateLegacyStarter()
        #expect(migrated == state)
    }
}
