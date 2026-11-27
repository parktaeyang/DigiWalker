import Foundation
import Testing
@testable import DigiWalkerCore

@Suite struct RebirthTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var day2: Date { start.addingTimeInterval(86400) }

    private func finished(seed: UInt64 = 3, steps: Int = Monster.stepsForNewEgg) -> GameState {
        var state = GameState.enrolledEgg(id: testPartnerId(seed), at: start)
        var generator = SeededGenerator(seed: seed)
        state.settle(day: start, steps: steps, distance: 900, at: start, using: &generator)
        return state
    }

    private func settle(_ state: inout GameState, day: Date, steps: Int, seed: UInt64 = 7) {
        var generator = SeededGenerator(seed: seed)
        state.settle(day: day, steps: steps, distance: nil, at: day, using: &generator)
    }

    @Test func thresholdIsUltimatePlusTenThousand() {
        #expect(Monster.stepsForNewEgg == 85_000)
        #expect(finished(steps: 84_999).monster.canStartNewEgg == false)
        #expect(finished(steps: 85_000).monster.canStartNewEgg)
    }

    @Test func refusesWithoutChangingAnything() throws {
        var notYet = finished(steps: 84_999)
        let beforeNotYet = notYet
        let applied1 = notYet.startNewEgg(target: notYet.monster.id, at: day2)
        #expect(!applied1)
        #expect(notYet == beforeNotYet)

        var wrongTarget = finished()
        let beforeWrong = wrongTarget
        let applied2 = wrongTarget.startNewEgg(target: testPartnerId(999), at: day2)
        #expect(!applied2)
        #expect(wrongTarget == beforeWrong)

        var egg = GameState.enrolledEgg(at: start)
        let beforeEgg = egg
        let applied3 = egg.startNewEgg(target: egg.monster.id, at: day2)
        #expect(!applied3)
        #expect(egg == beforeEgg)

        // A species the catalog does not know has no stage, so it never qualifies.
        var unknown = try LegacyFixtures.gameState(LegacyFixtures.unknown)
        settle(&unknown, day: day2, steps: 200_000)
        #expect(unknown.monster.stage == nil)
        let beforeUnknown = unknown
        let applied4 = unknown.startNewEgg(target: unknown.monster.id, at: day2)
        #expect(!applied4)
        #expect(unknown == beforeUnknown)
    }

    @Test func appliesAFreshEggAndKeepsTheGameWideRecords() throws {
        var state = finished()
        let before = state
        let newId = testPartnerId(500)
        let applied5 = state.startNewEgg(target: before.monster.id, at: day2, newMonsterId: newId)
        #expect(applied5)
        #expect(state.monster.id == newId)
        #expect(state.monster.isEgg)
        #expect(state.monster.speciesId == Monster.eggSpeciesId)
        #expect(state.monster.totalCreditedSteps == 0)
        #expect(state.monster.distanceMeters == 0)
        #expect(state.monster.cardId == nil)
        #expect(state.itemSegmentsRolled == 0)
        #expect(state.generation == 1)
        #expect(state.previousCardId == before.monster.cardId)
        #expect(state.revision == before.revision + 1)
        #expect(state.dex == before.dex)
        #expect(state.items == before.items)
        #expect(state.itemUses == before.itemUses)
        // The rebirth day (day2) has no ledger yet, so this equality does not exercise the move-aside; that is
        // covered by `newPartnerCountsOnlyFromItsStart`. It shows only that other days' ledgers are untouched.
        #expect(state.ledgers == before.ledgers)
        #expect(state.enrolledAt == before.enrolledAt)
        #expect(state.lastStepDay == before.lastStepDay)
        #expect(state.createdAt == before.createdAt)
        #expect(state.timeZone == before.timeZone)
        // The result still decodes (the checkpoint 0 matches 0 steps).
        #expect(try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(state)) == state)
    }

    @Test func repeatingTheSameTargetIsIgnored() {
        var state = finished()
        let target = state.monster.id
        let applied6 = state.startNewEgg(target: target, at: day2, newMonsterId: testPartnerId(500))
        #expect(applied6)
        let after = state
        let applied7 = state.startNewEgg(target: target, at: day2, newMonsterId: testPartnerId(501))
        #expect(!applied7)
        #expect(state == after)
    }

    @Test func newPartnerCountsOnlyFromItsStart() {
        var state = finished()
        let at = start.addingTimeInterval(3_600)
        let applied8 = state.startNewEgg(target: state.monster.id, at: at, newMonsterId: testPartnerId(500))
        #expect(applied8)
        #expect(state.partnerSince == at)
        #expect(state.stepCutoff == at)
        // The day's old ledger moved aside (daily maximum kept); the new partner starts the day at 0.
        let day = state.calendar.startOfDay(for: start)
        #expect(state.ledgers[day] == nil)
        #expect(state.priorPartnerLedgers[day]?.creditedSteps == Monster.stepsForNewEgg)
        let reborn = state
        // A read of an earlier day is ignored.
        settle(&state, day: start.addingTimeInterval(-86400), steps: 5_000)
        #expect(state == reborn)
        // Steps counted from the start of the new partner are paid once, as a high-water mark.
        settle(&state, day: start, steps: 600)
        settle(&state, day: start, steps: 600)
        #expect(state.monster.totalCreditedSteps == 600)
        #expect(!state.monster.isEgg)
        #expect(state.monster.stage == 0)
        #expect(state.previousCardId == nil)
        #expect(try! JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(state)) == state)
    }

    @MainActor @Test func stepsBetweenTheLastSettlementAndTheRebirthAreNotPaid() async throws {
        var state = finished(steps: Monster.stepsForNewEgg)
        let t = start.addingTimeInterval(7_200)
        // 600 steps were taken after the last settlement and before the rebirth: a read from the day start sees them.
        state.startNewEgg(target: state.monster.id, at: t, newMonsterId: testPartnerId(500))
        let first = try await GrowthService.reconcile(state, through: t.addingTimeInterval(60)) { metric, from, to in
            guard metric == .steps else { return nil }
            // Samples before `t` (even ones that synced late) exist only in ranges that start earlier.
            return from < t ? Double(Monster.stepsForNewEgg + 600) : 0
        }
        #expect(first.monster.totalCreditedSteps == 0)
        #expect(first.monster.isEgg)
        // Only steps after the rebirth are paid afterwards.
        let second = try await GrowthService.reconcile(first, through: t.addingTimeInterval(3_600)) { metric, from, _ in
            guard metric == .steps else { return nil }
            return from >= t ? 700 : Double(Monster.stepsForNewEgg + 600)
        }
        #expect(second.monster.totalCreditedSteps == 700)
        #expect(!second.monster.isEgg)
    }

    @MainActor @Test func lateSamplesFromBeforeTheRebirthNeverPayEitherDay() async throws {
        // Previous day's re-read window (lastStepDay - 1) and same-day re-read must both stay below the cutoff.
        var state = GameState.enrolledEgg(id: testPartnerId(3), at: start)
        var generator = SeededGenerator(seed: 3)
        state.settle(day: start, steps: 1_000, distance: nil, at: start, using: &generator)
        state.settle(day: day2, steps: Monster.stepsForNewEgg, distance: nil, at: day2, using: &generator)
        #expect(state.monster.canStartNewEgg)
        let t = day2.addingTimeInterval(1_800)
        state.startNewEgg(target: state.monster.id, at: t, newMonsterId: testPartnerId(501))
        let calendar = state.calendar
        let result = try await GrowthService.reconcile(state, through: t.addingTimeInterval(120)) { metric, from, to in
            guard metric == .steps else { return nil }
            // A late iPhone sample before `t` raises every window that begins earlier; windows from `t` are empty.
            return from < t ? 50_000 : 0
        }
        #expect(result.monster.totalCreditedSteps == 0)
        #expect(result.partnerSince == t)
        // The previous day was not read at all: its ledger is untouched.
        #expect(result.ledgers[calendar.startOfDay(for: start)] == state.ledgers[calendar.startOfDay(for: start)])
    }

    @MainActor @Test func rebirthJustBeforeMidnightPaysTheNextDayFromItsStart() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        var state = finished()
        let midnight = calendar.startOfDay(for: day2)
        let t = midnight.addingTimeInterval(-60)
        state.startNewEgg(target: state.monster.id, at: t, newMonsterId: testPartnerId(500))
        let now = midnight.addingTimeInterval(600)
        let result = try await GrowthService.reconcile(state, through: now) { metric, from, to in
            guard metric == .steps else { return nil }
            if from == t { return 40 }               // the last minute of the old day
            if from == midnight { return 700 }        // the new day
            return 99_999                             // anything else must not be read
        }
        #expect(result.monster.totalCreditedSteps == 740)
        #expect(result.stepCutoff == t)
    }

    @Test func startNeverMovesBeforeAnObservedMoment() throws {
        var state = finished()
        let observed = start.addingTimeInterval(7_200)
        state.recordObservation(steps: 10, at: observed)
        // A start earlier than the observation is raised to it.
        let applied = state.startNewEgg(target: state.monster.id, at: start.addingTimeInterval(60), newMonsterId: testPartnerId(500))
        #expect(applied)
        #expect(state.partnerSince == observed)
        // The second rebirth on the same day starts no earlier than the first and never pays the day twice.
        var second = state
        settle(&second, day: observed, steps: 40)
        let paid = second.priorPartnerLedgers[second.calendar.startOfDay(for: observed)]?.creditedSteps
        #expect(paid == Monster.stepsForNewEgg)
        #expect(second.monster.totalCreditedSteps == 40)
    }

    @Test func sameDayRebirthTwiceKeepsOneDailyMaximum() throws {
        var state = finished(steps: Monster.stepsForNewEgg)
        let t1 = start.addingTimeInterval(3_600)
        let firstApplied = state.startNewEgg(target: state.monster.id, at: t1, newMonsterId: testPartnerId(500))
        #expect(firstApplied)
        // The second partner is made finished by a big read from its own start.
        settle(&state, day: t1, steps: Monster.stepsForNewEgg)
        #expect(state.monster.canStartNewEgg)
        let t0 = start // earlier than the first cutoff: clamped
        let secondApplied = state.startNewEgg(target: state.monster.id, at: t0, newMonsterId: testPartnerId(501))
        #expect(secondApplied)
        #expect(state.partnerSince == t1)
        let day = state.calendar.startOfDay(for: start)
        #expect(state.ledgers[day] == nil)
        #expect(state.priorPartnerLedgers[day]?.creditedSteps == Monster.stepsForNewEgg * 2)
    }

    @Test func priorLedgersKeyIsRequiredFromGenerationOne() throws {
        var state = finished()
        _ = state.startNewEgg(target: state.monster.id, at: day2, newMonsterId: testPartnerId(500))
        func decode(_ change: (inout [String: Any]) -> Void) throws -> GameState {
            var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
            change(&root)
            return try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: root))
        }
        #expect(throws: Never.self) { try decode { _ in } }
        #expect(throws: DecodingError.self) { try decode { $0["priorPartnerLedgers"] = nil } }
        #expect(throws: DecodingError.self) { try decode { $0["priorPartnerLedgers"] = NSNull() } }
        // Generation 0 (legacy) may still lack it.
        let first = finished()
        var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(first)) as? [String: Any])
        root["priorPartnerLedgers"] = nil
        #expect(throws: Never.self) {
            try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: root))
        }
    }

    @Test func dexAndPreviousCardAreRequiredFromGenerationOne() throws {
        var state = finished()
        _ = state.startNewEgg(target: state.monster.id, at: day2, newMonsterId: testPartnerId(500))
        func decode(_ source: GameState, _ change: (inout [String: Any]) -> Void) throws -> GameState {
            var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
            change(&root)
            return try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: root))
        }
        #expect(throws: Never.self) { try decode(state) { _ in } }
        #expect(throws: DecodingError.self) { try decode(state) { $0["previousCardId"] = nil } }
        #expect(throws: DecodingError.self) { try decode(state) { $0["previousCardId"] = NSNull() } }
        #expect(throws: DecodingError.self) { try decode(state) { $0["dex"] = nil } }
        #expect(throws: DecodingError.self) { try decode(state) { $0["dex"] = [Any]() } }
        // A hatched generation-1 partner no longer carries previousCardId but keeps its dex.
        var hatched = state
        settle(&hatched, day: day2, steps: Monster.stepsToHatch)
        #expect(!hatched.monster.isEgg && hatched.previousCardId == nil)
        #expect(throws: Never.self) { try decode(hatched) { _ in } }
        #expect(throws: DecodingError.self) { try decode(hatched) { $0["dex"] = nil } }
        // Generation 0 keeps its legacy defaults (an unhatched legacy egg has neither key).
        #expect(throws: Never.self) { try decode(GameState.enrolledEgg(id: testPartnerId(9), at: start)) { $0["dex"] = nil; $0["previousCardId"] = nil } }
    }

    @Test func supersedesNeedsRevisionAndKeepsGenerationPerId() throws {
        let old = finished()
        var reborn = old
        _ = reborn.startNewEgg(target: old.monster.id, at: day2, newMonsterId: testPartnerId(500))
        #expect(reborn.snapshot.supersedes(old.snapshot))
        #expect(!old.snapshot.supersedes(reborn.snapshot))
        // Higher generation but not a higher revision: not a rebirth of the cached partner.
        let stale = MonsterSnapshot(schemaVersion: 4, revision: old.revision, createdAt: old.createdAt,
                                    monster: reborn.monster, todaySteps: nil, observedAt: nil, timeZone: old.timeZone,
                                    dex: reborn.dex, items: reborn.itemSummaries, generation: 1)
        #expect(!stale.supersedes(old.snapshot))
        // The same partner id with another generation is rejected.
        let forged = MonsterSnapshot(schemaVersion: 4, revision: old.revision + 5, createdAt: old.createdAt,
                                     monster: old.monster, todaySteps: nil, observedAt: nil, timeZone: old.timeZone,
                                     dex: old.dex, items: old.itemSummaries, generation: 1)
        #expect(!forged.supersedes(old.snapshot))
    }

    @Test func partnerSinceAndGenerationMustComeTogether() throws {
        var state = finished()
        _ = state.startNewEgg(target: state.monster.id, at: day2, newMonsterId: testPartnerId(500))
        func decode(_ change: (inout [String: Any]) -> Void) throws -> GameState {
            var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
            change(&root)
            return try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: root))
        }
        #expect(throws: Never.self) { try decode { _ in } }
        #expect(throws: DecodingError.self) { try decode { $0["partnerSince"] = nil } }
        #expect(throws: DecodingError.self) { try decode { $0["generation"] = 0 } }
        #expect(throws: DecodingError.self) { try decode { $0["partnerSince"] = NSNull() } }
        let first = finished()
        var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(first)) as? [String: Any])
        root["partnerSince"] = 5.0
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: root))
        }
    }

    @MainActor @Test func catchUpAcrossDaysDoesNotRepayEarlierDays() async throws {
        var state = finished()
        let applied9 = state.startNewEgg(target: state.monster.id, at: start, newMonsterId: testPartnerId(500))
        #expect(applied9)
        let now = day2.addingTimeInterval(600)
        let result = try await GrowthService.reconcile(state, through: now) { metric, from, _ in
            guard metric == .steps else { return nil }
            return from == start ? 300 : 400
        }
        #expect(result.monster.id == testPartnerId(500))
        #expect(result.monster.totalCreditedSteps == 700)
        #expect(result.generation == 1)
    }

    @Test func hatchIsDeterministicAndNeverReusesThePreviousCard() throws {
        var firstCards = Set<String>()
        for seed in 0..<300 as Range<UInt64> {
            let previous = finished(seed: seed % 11 + 1)
            let previousCard = try #require(previous.monster.cardId)
            let newId = testPartnerId(10_000 + seed)
            func hatched() -> GameState {
                var state = previous
                _ = state.startNewEgg(target: state.monster.id, at: day2, newMonsterId: newId)
                // Different evolution generators must not change the hatching.
                settle(&state, day: day2, steps: 500, seed: seed &* 31 &+ 1)
                return state
            }
            let one = hatched(), two = hatched()
            #expect(one.monster.cardId == two.monster.cardId)
            #expect(one.monster.speciesId == two.monster.speciesId)
            #expect(one.monster.cardId != previousCard)
            firstCards.insert(try #require(one.monster.cardId))
        }
        #expect(firstCards.count >= SpeciesCatalog.cards.count - 1)
    }

    @Test func theCardBeforeThePreviousOneMayComeBack() throws {
        var seen = false
        for seed in 0..<400 as Range<UInt64> {
            var state = finished(seed: 4)
            let firstCard = try #require(state.monster.cardId)
            state.startNewEgg(target: state.monster.id, at: day2, newMonsterId: testPartnerId(2_000 + seed))
            settle(&state, day: day2, steps: 500)
            #expect(state.monster.cardId != firstCard)
            // Finish the second partner, then hatch a third one.
            settle(&state, day: day2, steps: Monster.stepsForNewEgg + 500, seed: seed)
            guard state.monster.canStartNewEgg else { continue }
            let secondCard = state.monster.cardId
            state.startNewEgg(target: state.monster.id, at: day2, newMonsterId: testPartnerId(3_000 + seed))
            settle(&state, day: day2.addingTimeInterval(86400), steps: 600)
            #expect(state.monster.cardId != secondCard)
            if state.monster.cardId == firstCard { seen = true }
        }
        #expect(seen)
    }

    @Test func hatchingDoesNotConsumeTheEvolutionGenerator() {
        var state = finished()
        state.startNewEgg(target: state.monster.id, at: day2, newMonsterId: testPartnerId(500))
        var counting = CountingGenerator(seed: 1)
        state.settle(day: day2, steps: 500, distance: nil, at: day2, using: &counting)
        #expect(!state.monster.isEgg)
        #expect(counting.draws == 0)
        state.settle(day: day2, steps: 75_000, distance: nil, at: day2, using: &counting)
        #expect(counting.draws == 5) // stages 1...5, none for the hatch
    }

    @Test func newPartnerRollsItemsFromSegmentOneWithItsOwnSeed() throws {
        var state = finished()
        let oldItems = state.items
        let newId = testPartnerId(500)
        state.startNewEgg(target: state.monster.id, at: day2, newMonsterId: newId)
        settle(&state, day: day2, steps: 25_000)
        #expect(state.itemSegmentsRolled == 5)
        let fresh = state.items.dropFirst(oldItems.count)
        #expect(Array(state.items.prefix(oldItems.count)) == oldItems)
        let expected = (1...5).compactMap { s in ItemDrop.roll(monsterId: newId, segment: s, preferred: []).map { _ in s } }
        // Preference may change which item, never whether a segment drops.
        #expect(fresh.map(\.segment) == expected)
        #expect(fresh.allSatisfy { $0.monsterId == newId })
        var keys = Set<String>()
        #expect(state.items.allSatisfy { keys.insert("\($0.monsterId)#\($0.segment)").inserted })
        #expect(try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(state)) == state)
    }

    @Test func legacyFilesIgnoreExperienceAndCreditedXP() throws {
        var state = try LegacyFixtures.gameState(LegacyFixtures.botamon)
        #expect(state.generation == 0)
        #expect(state.itemUses.isEmpty)
        let text = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        #expect(!text.contains("experience"))
        #expect(!text.contains("creditedXP"))
        let before = state
        settle(&state, day: Date(timeIntervalSinceReferenceDate: 821750400), steps: 10)
        #expect(state.monster.totalCreditedSteps == before.monster.totalCreditedSteps)
        let snapshot = try JSONDecoder().decode(MonsterSnapshot.self, from: Data(LegacyFixtures.snapshotV1.utf8))
        #expect(snapshot.supersedes(nil))
        #expect(!String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self).contains("experience"))
    }

    @Test func refusesAnIdAlreadyInUse() {
        var state = finished()
        let before = state
        let current = state.monster.id
        let sameId = state.startNewEgg(target: current, at: day2, newMonsterId: current)
        #expect(!sameId)
        if let grant = state.items.first {
            let grantedId = state.startNewEgg(target: current, at: day2, newMonsterId: grant.monsterId)
            #expect(!grantedId)
        }
        #expect(state == before)
    }

    @MainActor @Test func rebirthAfterTheClockWentBackDoesNotRepayStepsAlreadyCredited() async throws {
        var state = finished(steps: Monster.stepsForNewEgg)
        let t1300 = start.addingTimeInterval(3_600)
        let t1230 = start.addingTimeInterval(1_800)
        state = try await GrowthService.reconcile(state, through: t1300) { metric, _, _ in
            metric == .steps ? Double(Monster.stepsForNewEgg + 300) : nil
        }
        // The clock is set back and a lower value arrives: the display time moves back, the credit does not.
        state = try await GrowthService.reconcile(state, through: t1230) { metric, _, _ in
            metric == .steps ? Double(Monster.stepsForNewEgg + 100) : nil
        }
        #expect(state.observedAt == t1230)
        #expect(state.creditedThrough == t1300)
        let t1231 = start.addingTimeInterval(1_860)
        let applied = state.startNewEgg(target: state.monster.id, at: t1231, newMonsterId: testPartnerId(500))
        #expect(applied)
        #expect(state.partnerSince == t1300)
        let reborn = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(state))
        #expect(reborn == state)
        #expect(reborn.creditedThrough == t1300)
    }

    @MainActor @Test func filesWithoutCreditedThroughFallBackToObservedAt() async throws {
        var state = finished(steps: Monster.stepsForNewEgg)
        let t1300 = start.addingTimeInterval(3_600)
        state = try await GrowthService.reconcile(state, through: t1300) { metric, _, _ in
            metric == .steps ? Double(Monster.stepsForNewEgg) : nil
        }
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        #expect(json.removeValue(forKey: "creditedThrough") != nil)
        var legacy = try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.creditedThrough == nil)
        let applied = legacy.startNewEgg(target: legacy.monster.id, at: start, newMonsterId: testPartnerId(500))
        #expect(applied)
        #expect(legacy.partnerSince == t1300)
    }
}
