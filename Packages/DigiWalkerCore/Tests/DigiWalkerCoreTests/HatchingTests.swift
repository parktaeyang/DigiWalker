import Foundation
import Testing
@testable import DigiWalkerCore

@Suite struct HatchingTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func hatchesExactlyAt500AcrossDaysAndSurvivesReplay() throws {
        var state = GameState(now: start, timeZone: .gmt)
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
        let baby = try #require(state.monster.hatchling)
        #expect(state.monster.name == baby.name)
        #expect(state.monster.totalCreditedSteps == 500)
        #expect(state.monster.id == eggID)
        #expect(state.monster.experience == 40) // Daily thresholds: 499 and 1.
        #expect(state.snapshot.supersedes(before))
        var restored = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(state))
        restored.settle(day: tomorrow, steps: 1, distance: nil)
        #expect(restored == state)
        restored.settle(day: tomorrow, steps: 2500, distance: nil)
        #expect(restored.monster.hatchling == baby)
    }

    @Test func firstLargeReadingHatchesImmediately() throws {
        var state = GameState(now: start, timeZone: .gmt)
        state.enroll(at: start)
        state.settle(day: start, steps: 803, distance: nil)
        #expect(state.monster.hatchling != nil)
        #expect(state.monster.totalCreditedSteps == 803)
        #expect(state.monster.experience == 80)
    }

    @Test(arguments: [0, 499, 500, 850]) func migrateSavedStarter(steps: Int) throws {
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
        #expect((state.monster.hatchling != nil) == (steps >= 500))
        let migrated = state
        state.migrateLegacyStarter()
        #expect(migrated == state)
    }
}
