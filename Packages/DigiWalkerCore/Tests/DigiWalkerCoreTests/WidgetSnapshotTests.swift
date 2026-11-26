import Foundation
import Testing
@testable import DigiWalkerCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

private func egg() -> GameState { GameState.fixedEgg(now: t0) }

/// Same-day settlement: the daily credit only ever grows, so a larger `steps` adds the difference.
private func settled(_ state: GameState, steps: Int) -> GameState {
    var next = state
    var generator = SeededGenerator(seed: 7)
    next.settle(day: t0, steps: steps, distance: nil, at: nil, using: &generator)
    return next
}

private func enrolledEgg() -> GameState {
    var state = egg()
    state.enroll(at: t0)
    return state
}

private func stage(_ n: Int, steps: Int? = nil) -> GameState {
    settled(enrolledEgg(), steps: steps ?? EvolutionCard.requiredSteps(stage: n))
}

struct WidgetSnapshotTests {
    @Test func eggCountsDownToHatch() {
        var state = egg()
        var snapshot = WidgetSnapshot(state: state, now: t0)
        #expect(snapshot.isEgg)
        #expect(snapshot.nextRequiredSteps == Monster.stepsToHatch)
        #expect(snapshot.remainingSteps == Monster.stepsToHatch)
        state.enroll(at: t0)
        snapshot = WidgetSnapshot(state: state, now: t0)
        #expect(snapshot.remainingSteps == 500)
    }

    @Test func remainingUsesRequiredStepsOfNextStage() {
        let baby = stage(0, steps: 1_000)
        let snapshot = WidgetSnapshot(state: baby, now: t0)
        #expect(snapshot.stage == 0)
        #expect(snapshot.nextRequiredSteps == EvolutionCard.requiredSteps(stage: 1))
        #expect(snapshot.remainingSteps == EvolutionCard.requiredSteps(stage: 1) - 1_000)
    }

    @Test func finalStageHasNoNext() {
        let final = stage(5)
        let snapshot = WidgetSnapshot(state: final, now: t0)
        #expect(snapshot.stage == EvolutionCard.stageCount - 1)
        #expect(snapshot.nextRequiredSteps == nil)
        #expect(snapshot.remainingSteps == nil)
    }

    @Test func schemaVersionRoundTripsAndSupportsOnlyKnownVersions() throws {
        let snapshot = WidgetSnapshot(state: egg(), now: t0)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        #expect(decoded == snapshot)
        #expect(WidgetSnapshot.supportedSchemaVersions.contains(decoded.schemaVersion))
        #expect(!WidgetSnapshot.supportedSchemaVersions.contains(99))
    }

    @Test func sameDisplayIgnoresRevisionAndTime() {
        let state = enrolledEgg()
        let a = WidgetSnapshot(state: state, now: t0)
        let b = WidgetSnapshot(state: state, now: t0.addingTimeInterval(10))
        #expect(a != b)
        #expect(a.sameDisplay(as: b))
    }
}

struct WidgetReloadPolicyTests {
    private func make(steps: Int, state: GameState) -> (WidgetSnapshot, GameState) {
        let next = settled(state, steps: steps)
        return (WidgetSnapshot(state: next, now: t0), next)
    }

    @Test func noPreviousAlwaysReloads() {
        let next = WidgetSnapshot(state: stage(0, steps: 600), now: t0)
        #expect(WidgetReloadPolicy.shouldReload(previous: nil, next: next, foreground: false, lastReload: nil, now: t0))
    }

    @Test func unchangedDoesNotReload() {
        let snapshot = WidgetSnapshot(state: stage(0, steps: 600), now: t0)
        #expect(!WidgetReloadPolicy.shouldReload(
            previous: snapshot, next: snapshot, foreground: true, lastReload: t0, now: t0.addingTimeInterval(9_999)))
    }

    @Test func speciesChangeAlwaysReloadsEvenInBackgroundRightAfterReload() {
        let baby = stage(0, steps: 600)
        let (grown, _) = make(steps: EvolutionCard.requiredSteps(stage: 1), state: baby)
        let before = WidgetSnapshot(state: baby, now: t0)
        #expect(grown.speciesId != before.speciesId)
        #expect(WidgetReloadPolicy.shouldReload(
            previous: before, next: grown, foreground: false, lastReload: t0, now: t0.addingTimeInterval(1)))
    }

    @Test func stepOnlyChangeWaitsThirtyMinutesInBackground() {
        let baby = stage(0, steps: 600)
        let (moreSteps, _) = make(steps: 900, state: baby)
        let before = WidgetSnapshot(state: baby, now: t0)
        #expect(moreSteps.sameLook(as: before))
        #expect(!moreSteps.sameDisplay(as: before))
        func decide(after seconds: TimeInterval) -> Bool {
            WidgetReloadPolicy.shouldReload(previous: before, next: moreSteps, foreground: false,
                                            lastReload: t0, now: t0.addingTimeInterval(seconds))
        }
        #expect(!decide(after: 29 * 60))
        #expect(decide(after: 30 * 60))
        #expect(decide(after: 31 * 60))
    }

    @Test func stepOnlyChangeReloadsInForeground() {
        let baby = stage(0, steps: 600)
        let (moreSteps, _) = make(steps: 900, state: baby)
        let before = WidgetSnapshot(state: baby, now: t0)
        #expect(WidgetReloadPolicy.shouldReload(
            previous: before, next: moreSteps, foreground: true, lastReload: t0, now: t0.addingTimeInterval(5)))
    }

    @Test func timeComparisonUsesTimeIntervalNotInt() {
        // 30 minutes minus a fraction of a second is still too early.
        let baby = stage(0, steps: 600)
        let (moreSteps, _) = make(steps: 900, state: baby)
        let before = WidgetSnapshot(state: baby, now: t0)
        #expect(!WidgetReloadPolicy.shouldReload(
            previous: before, next: moreSteps, foreground: false, lastReload: t0,
            now: t0.addingTimeInterval(WidgetReloadPolicy.stepOnlyInterval - 0.5)))
    }
}

struct PixelScalingTests {
    @Test func wholeNumberFactorFitsTheBox() {
        // 64x56 sprite, 40pt box at @2x = 80 device pixels: only k = 1 fits.
        #expect(PixelScaling.factor(availablePoints: 40, spritePixels: 64, displayScale: 2) == 1)
        // 32px sprite in 40pt at @2x = 80 pixels: k = 2.
        #expect(PixelScaling.factor(availablePoints: 40, spritePixels: 32, displayScale: 2) == 2)
    }

    @Test func tooSmallOrBadInputFallsBackToOne() {
        #expect(PixelScaling.factor(availablePoints: 10, spritePixels: 64, displayScale: 2) == 1)
        #expect(PixelScaling.factor(availablePoints: .nan, spritePixels: 64, displayScale: 2) == 1)
        #expect(PixelScaling.factor(availablePoints: 40, spritePixels: 0, displayScale: 2) == 1)
        #expect(PixelScaling.factor(availablePoints: .infinity, spritePixels: 1, displayScale: 2) == 1)
    }
}

struct WidgetDisplayRulesTests {
    @Test func stepsBeyondTheLastStageAreNotAVisibleChange() {
        let final = stage(5)
        let more = settled(final, steps: EvolutionCard.requiredSteps(stage: 5) + 3_000)
        let before = WidgetSnapshot(state: final, now: t0)
        let after = WidgetSnapshot(state: more, now: t0)
        #expect(after.totalCreditedSteps > before.totalCreditedSteps)
        #expect(after.sameDisplay(as: before))
        #expect(!WidgetReloadPolicy.shouldReload(
            previous: before, next: after, foreground: true, lastReload: t0, now: t0.addingTimeInterval(9_999)))
    }

    @Test func remainingStepsChangeIsAVisibleChange() {
        let baby = stage(0, steps: 600)
        let more = settled(baby, steps: 900)
        #expect(!WidgetSnapshot(state: more, now: t0).sameDisplay(as: WidgetSnapshot(state: baby, now: t0)))
    }

    @Test func progressNamesHatchEvolutionAndFinalStage() {
        #expect(WidgetSnapshot(state: enrolledEgg(), now: t0).progress == .hatch(remaining: Monster.stepsToHatch))
        let baby = WidgetSnapshot(state: stage(0, steps: 1_000), now: t0)
        #expect(baby.progress == .evolution(remaining: EvolutionCard.requiredSteps(stage: 1) - 1_000))
        #expect(WidgetSnapshot(state: stage(5), now: t0).progress == .finalStage)
    }

    @Test func unknownStageIsNeverShownAsFinal() throws {
        // A copy whose stage is unknown has no next stage either; it must not claim the final stage.
        let json = """
        {"schemaVersion":1,"monsterId":"00000000-0000-0000-0000-000000000001","speciesId":"x","name":"X",
         "isEgg":false,"totalCreditedSteps":10,"revision":1,"updatedAt":0}
        """
        let unknown = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(unknown.stage == nil)
        #expect(unknown.remainingSteps == nil)
        #expect(unknown.progress == .unknown)
    }
}

struct WidgetTimelineRetryTests {
    @Test func unreadableCopyIsRetriedAndReadableOneIsNot() {
        #expect(WidgetTimelineRetry.nextRefresh(copyReadable: true, now: t0) == nil)
        let retry = WidgetTimelineRetry.nextRefresh(copyReadable: false, now: t0)
        #expect(retry == t0.addingTimeInterval(WidgetTimelineRetry.interval))
        #expect((15 * 60...30 * 60).contains(WidgetTimelineRetry.interval))
    }
}
