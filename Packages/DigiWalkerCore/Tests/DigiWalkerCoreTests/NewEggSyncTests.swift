import Foundation
import Testing
@testable import DigiWalkerCore

@Suite struct NewEggSyncTests {
    private let start = LegacyFixtures.createdAt

    private func settle(_ state: inout GameState, steps: Int, seed: UInt64 = 7) {
        var generator = SeededGenerator(seed: seed)
        state.settle(day: start, steps: steps, distance: nil, at: nil, using: &generator)
    }

    private func enrolled(id: UUID = testPartnerId(1)) -> GameState {
        GameState.enrolledEgg(id: id, at: start)
    }

    private func replaced(_ state: GameState, newId: UInt64) -> GameState {
        var next = state
        let applied = next.startNewEgg(target: state.monster.id, at: start, newMonsterId: testPartnerId(newId))
        #expect(applied)
        return next
    }

    // MARK: Snapshot v4

    @Test func v4NeedsGenerationAndOlderVersionsMustNotHaveIt() {
        let state = enrolled()
        func make(_ version: Int, generation: Int?) -> MonsterSnapshot {
            MonsterSnapshot(schemaVersion: version, revision: state.revision, createdAt: state.createdAt,
                            monster: state.monster, todaySteps: nil, observedAt: nil, timeZone: .gmt,
                            dex: state.dex, items: state.itemSummaries, generation: generation)
        }
        #expect(make(4, generation: 0).supersedes(nil))
        #expect(!make(4, generation: nil).supersedes(nil))
        #expect(!make(4, generation: -1).supersedes(nil))
        #expect(!make(3, generation: 0).supersedes(nil))
        #expect(!make(2, generation: 0).supersedes(nil))
        #expect(make(3, generation: nil).supersedes(nil))
    }

    @Test func v3AndV4DecodeAndV4RoundTrips() throws {
        var state = enrolled()
        settle(&state, steps: 2_000)
        let v4 = state.snapshot
        let decoded = try JSONDecoder().decode(MonsterSnapshot.self, from: JSONEncoder().encode(v4))
        #expect(decoded == v4)
        // v3 JSON (no generation, no experience in the monster) still decodes.
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(v4)) as? [String: Any])
        object["schemaVersion"] = 3
        object["generation"] = nil
        let v3 = try JSONDecoder().decode(MonsterSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(v3.generation == nil)
        #expect(v3.supersedes(nil))
    }

    @Test func newEggSnapshotReplacesTheOldPartnerAtTheSameCreatedAt() {
        var state = enrolled()
        settle(&state, steps: Monster.stepsForNewEgg)
        let old = state.snapshot
        let next = replaced(state, newId: 2)
        let fresh = next.snapshot
        #expect(fresh.createdAt == old.createdAt)
        #expect(fresh.generation == 1)
        // Arrival order one: old first, then new.
        #expect(fresh.supersedes(old))
        // Arrival order two: the new one is cached and a late snapshot of the old partner arrives.
        #expect(!old.supersedes(fresh))
        // A v3 cache of the old partner (no generation) is replaced too.
        let v3 = MonsterSnapshot(schemaVersion: 3, revision: old.revision, createdAt: old.createdAt,
                                 monster: old.monster, todaySteps: nil, observedAt: nil, timeZone: .gmt,
                                 dex: old.dex, items: old.items)
        #expect(fresh.supersedes(v3))
    }

    @Test func reinstallReplacesAHigherGenerationCacheAndNotTheOtherWayAround() {
        var state = enrolled()
        settle(&state, steps: Monster.stepsForNewEgg)
        let gen1 = replaced(state, newId: 2).snapshot
        // Another partner id (a generation never changes under one id), with a higher revision.
        let otherPartner = replaced(state, newId: 3).snapshot.monster
        let cachedGen2 = MonsterSnapshot(schemaVersion: 4, revision: gen1.revision + 5, createdAt: gen1.createdAt,
                                         monster: otherPartner, todaySteps: nil, observedAt: nil, timeZone: .gmt,
                                         dex: gen1.dex, items: gen1.items, generation: 2)
        #expect(cachedGen2.supersedes(gen1))
        // Reinstall: later createdAt, generation 0.
        let reinstall = GameState.enrolledEgg(id: testPartnerId(9), at: start.addingTimeInterval(60)).snapshot
        #expect(reinstall.generation == 0)
        #expect(reinstall.supersedes(cachedGen2))
        #expect(!cachedGen2.supersedes(reinstall))
        // Same generation, different partner, same createdAt: neither wins.
        let sibling = GameState.enrolledEgg(id: testPartnerId(10), at: start).snapshot
        let other = GameState.enrolledEgg(id: testPartnerId(11), at: start).snapshot
        #expect(!sibling.supersedes(other))
    }

    @Test func v4NeedsGenerationNotAboveRevision() {
        var state = enrolled()
        settle(&state, steps: Monster.stepsForNewEgg)
        let base = replaced(state, newId: 2).snapshot
        func make(generation: Int) -> MonsterSnapshot {
            MonsterSnapshot(schemaVersion: 4, revision: base.revision, createdAt: base.createdAt, monster: base.monster,
                            todaySteps: nil, observedAt: nil, timeZone: .gmt, dex: base.dex, items: base.items,
                            generation: generation)
        }
        #expect(make(generation: base.revision).supersedes(nil))
        #expect(!make(generation: base.revision + 1).supersedes(nil))
    }

    @Test func realV3SnapshotOfThePreviousPartnerIsRejectedAfterAGen1Cache() throws {
        var state = enrolled()
        settle(&state, steps: Monster.stepsForNewEgg)
        let old = state.snapshot
        let gen1 = replaced(state, newId: 2).snapshot
        // A v3 JSON as the old watch wrote it: no generation, and the monster still carried `experience`.
        var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        root["schemaVersion"] = 3
        root["generation"] = nil
        var monster = try #require(root["monster"] as? [String: Any])
        monster["experience"] = 1234
        root["monster"] = monster
        let v3 = try JSONDecoder().decode(MonsterSnapshot.self, from: JSONSerialization.data(withJSONObject: root))
        #expect(v3.generation == nil)
        #expect(!v3.supersedes(gen1))
        #expect(gen1.supersedes(v3))
    }

    @Test func clockGoingBackwardsOnReinstallKeepsTheHigherGenerationCache() {
        var state = enrolled()
        settle(&state, steps: Monster.stepsForNewEgg)
        let gen1 = replaced(state, newId: 2).snapshot
        // A reinstall whose createdAt is earlier than the cache (clock went back): it must not replace it.
        let earlier = GameState.enrolledEgg(id: testPartnerId(9), at: start.addingTimeInterval(-3_600)).snapshot
        #expect(!earlier.supersedes(gen1))
    }

    @Test func v4JSONWithoutGenerationIsRejected() throws {
        var state = enrolled()
        settle(&state, steps: Monster.stepsForNewEgg)
        var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(replaced(state, newId: 2).snapshot)) as? [String: Any])
        root["generation"] = nil
        let decoded = try JSONDecoder().decode(MonsterSnapshot.self, from: JSONSerialization.data(withJSONObject: root))
        #expect(decoded.schemaVersion == 4)
        #expect(!decoded.supersedes(nil))
    }

    @Test func sameLookStateKeepsRevisionRuleAcrossGenerations() {
        var state = enrolled()
        settle(&state, steps: Monster.stepsForNewEgg)
        let next = replaced(state, newId: 2)
        let a = next.snapshot
        var later = next
        later.recordObservation(steps: 5, at: start)
        #expect(later.snapshot.supersedes(a))
        #expect(!a.supersedes(later.snapshot))
    }

    // MARK: Event

    @Test func newEggReadyFiresOnlyWhenCrossingTheThreshold() throws {
        var before = enrolled()
        settle(&before, steps: Monster.stepsForNewEgg - 1)
        var after = before
        settle(&after, steps: Monster.stepsForNewEgg)
        let event = try #require(GrowthEvent.newEggReady(between: before, after))
        #expect(event.kind == .newEggReady)
        #expect(event.id == "\(after.monster.id.uuidString)-newegg")
        #expect(event.title.contains(after.monster.name))
        #expect(event.title.hasSuffix("끝까지 걸었어요!"))
        #expect(event.body.contains("새 알"))
        // Not again once past the threshold.
        var later = after
        settle(&later, steps: Monster.stepsForNewEgg + 5_000)
        #expect(GrowthEvent.newEggReady(between: after, later) == nil)
        // A partner that was already past it when loaded gets none.
        #expect(GrowthEvent.newEggReady(between: later, later) == nil)
        // Not crossed.
        #expect(GrowthEvent.newEggReady(between: before, before) == nil)
        // Hatch/evolution/item helpers never produce it.
        #expect(GrowthEvent.between(before, after)?.kind != .newEggReady)
    }

    @Test func newEggReadyIsNilForAnotherPartnerAndFollowsEvolutionInOneBigSettlement() throws {
        var before = enrolled()
        settle(&before, steps: 10_000)
        var big = before
        settle(&big, steps: 90_000)
        let evolved = try #require(GrowthEvent.between(before, big))
        let ready = try #require(GrowthEvent.newEggReady(between: before, big))
        #expect(evolved.kind == .evolved)
        #expect(ready.kind == .newEggReady)
        #expect(ready.id != evolved.id)
        let otherPartner = replaced(big, newId: 2)
        #expect(GrowthEvent.newEggReady(between: big, otherPartner) == nil)
        #expect(GrowthEvent.newEggReady(between: before, enrolled(id: testPartnerId(5))) == nil)
    }

    @Test func newEggReadyEventRoundTripsAndOldQueuesStillDecode() throws {
        var before = enrolled()
        settle(&before, steps: Monster.stepsForNewEgg - 1)
        var after = before
        settle(&after, steps: Monster.stepsForNewEgg)
        let event = try #require(GrowthEvent.newEggReady(between: before, after))
        let decoded = try JSONDecoder().decode([GrowthEvent].self, from: JSONEncoder().encode([event]))
        #expect(decoded == [event])
        #expect(decoded.first?.title == event.title)
        let hatch = try #require(GrowthEvent.between(enrolled(), { var s = enrolled(); settle(&s, steps: 600); return s }()))
        let old = try JSONDecoder().decode([GrowthEvent].self, from: JSONEncoder().encode([hatch]))
        #expect(old == [hatch])
    }

    // MARK: Request

    @Test func requestRoundTripsWithItsTarget() throws {
        let request = NewEggRequest(targetMonsterId: testPartnerId(4), requestedAt: start)
        let data = try JSONEncoder().encode(request)
        #expect(try JSONDecoder().decode(NewEggRequest.self, from: data) == request)
        #expect(NewEggRequest.userInfoKey == "new_egg_request")
        let again = NewEggRequest(targetMonsterId: testPartnerId(4), requestedAt: start)
        #expect(again.targetMonsterId == request.targetMonsterId && again.requestId != request.requestId)
    }
}
