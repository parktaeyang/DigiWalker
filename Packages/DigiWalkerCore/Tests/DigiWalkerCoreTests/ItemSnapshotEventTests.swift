import Foundation
import Testing
@testable import DigiWalkerCore

@Suite struct ItemSnapshotEventTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// A partner that has found at least two items (fixed ids, so the same partner every run).
    private func withItems() throws -> GameState {
        for n in 1...500 as ClosedRange<UInt64> {
            var state = GameState.enrolledEgg(id: testPartnerId(n), at: start)
            var generator = SeededGenerator(seed: 1)
            state.settle(day: start, steps: 40_000, distance: nil, at: start, using: &generator)
            if state.items.count >= 2 { return state }
        }
        throw CocoaError(.fileReadUnknown)
    }

    private func snapshot(_ state: GameState, version: Int, dex: Bool = true, items: [ItemSummary]?) -> MonsterSnapshot {
        MonsterSnapshot(schemaVersion: version, revision: state.revision, createdAt: state.createdAt,
                        monster: state.monster, todaySteps: nil, observedAt: nil, timeZone: .gmt,
                        dex: dex ? state.dex : nil, items: items)
    }

    private func summary(_ id: String, count: Int = 1, current: Int? = nil) -> ItemSummary {
        ItemSummary(itemId: id, count: count, firstGrantedAt: start, currentPartnerCount: current ?? count)
    }

    @Test func v3RoundTripsAndCarriesAnItemSummary() throws {
        let state = try withItems()
        let published = state.snapshot
        #expect(published.schemaVersion == 4 && published.items == state.itemSummaries)
        #expect(published.items?.map(\.count).reduce(0, +) == state.items.count)
        #expect(published.supersedes(nil))
        let decoded = try JSONDecoder().decode(MonsterSnapshot.self, from: JSONEncoder().encode(published))
        #expect(decoded == published)
        // An empty list is a valid v3.
        let empty = GameState.fixedEgg(now: start).snapshot
        #expect(empty.items == [] && empty.supersedes(nil))
    }

    @Test func summaryCountsDuplicatesAndFirstGrantTime() throws {
        var state = GameState.enrolledEgg(id: testPartnerId(5), at: start)
        var generator = SeededGenerator(seed: 1)
        state.settle(day: start, steps: 20_000, distance: nil, at: start, using: &generator)
        var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        let id = state.monster.id.uuidString
        root["items"] = [(1, "digicore", 10.0), (2, "digicode", 20.0), (4, "digicore", 5.0)].map {
            ["itemId": $0.1, "monsterId": id, "segment": $0.0, "grantedAt": $0.2]
        }
        let loaded = try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: root))
        let summaries = loaded.itemSummaries
        #expect(summaries.map(\.itemId) == ["digicore", "digicode"])
        #expect(summaries.map(\.count) == [2, 1])
        #expect(summaries[0].firstGrantedAt == Date(timeIntervalSinceReferenceDate: 5))
        #expect(loaded.snapshot.supersedes(nil))
    }

    @Test func snapshotStaysSmallWhateverTheLedgerHolds() throws {
        // 5,000 grants of an earlier partner over all 25 items: the ledger is large, the snapshot is not.
        var state = GameState.enrolledEgg(id: testPartnerId(6), at: start)
        var generator = SeededGenerator(seed: 1)
        state.settle(day: start, steps: 100_000, distance: nil, at: start, using: &generator)
        var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        let other = testPartnerId(77).uuidString
        let ids = ItemCatalog.ids
        root["items"] = (1...5_000).map {
            ["itemId": ids[$0 % ids.count], "monsterId": other, "segment": $0, "grantedAt": Double($0)]
        }
        let loaded = try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: root))
        #expect(loaded.items.count == 5_000)
        let snapshot = loaded.snapshot
        #expect(snapshot.items?.count == 25 && snapshot.supersedes(nil))
        let size = try JSONEncoder().encode(snapshot).count
        #expect(size < 8_192, "snapshot is \(size) bytes")
        #expect(try JSONEncoder().encode(loaded.items).count > 100_000)
    }

    @Test func v3WithoutItemsOrWithBadItemsIsRejected() throws {
        let state = try withItems()
        let good = state.itemSummaries
        #expect(!snapshot(state, version: 3, items: nil).supersedes(nil))
        #expect(snapshot(state, version: 3, items: good).supersedes(nil))
        #expect(!snapshot(state, version: 3, items: good + [good[0]]).supersedes(nil)) // duplicate id
        #expect(!snapshot(state, version: 3, items: [summary("digicore", count: 0, current: 0)]).supersedes(nil))
        #expect(!snapshot(state, version: 3, items: [summary("digicore", count: 2, current: 3)]).supersedes(nil))
        #expect(!snapshot(state, version: 3, items: [summary("digicore", count: 2, current: -1)]).supersedes(nil))
        #expect(!snapshot(state, version: 3, items: [summary("")]).supersedes(nil))
        // The current partner cannot have found more than it has 5,000-step segments.
        let segments = ItemDrop.segment(forSteps: state.monster.totalCreditedSteps)
        #expect(snapshot(state, version: 3, items: [summary("digicore", count: segments)]).supersedes(nil))
        #expect(!snapshot(state, version: 3, items: [summary("digicore", count: segments + 1)]).supersedes(nil))
        #expect(!snapshot(state, version: 3, items: [summary("digicore", count: segments), summary("digicode")]).supersedes(nil))
        // Items of an earlier partner are not limited by the current partner's steps.
        #expect(snapshot(state, version: 3, items: [summary("digicore", count: segments + 5, current: 0)]).supersedes(nil))
    }

    @Test func hugeCurrentPartnerCountsCannotOverflowTheValidation() throws {
        let state = try withItems()
        let big = Int.max - 1
        #expect(!snapshot(state, version: 3, items: [summary("digicore", count: Int.max, current: big),
                                                      summary("digicode", count: Int.max, current: big)]).supersedes(nil))
        #expect(!snapshot(state, version: 3, items: [summary("digicore", count: Int.max, current: Int.max)]).supersedes(nil))
    }

    @Test func itemEventWithAnUnusableSegmentIsRejectedWhenDecoded() throws {
        let after = try withItems()
        var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(after)) as? [String: Any])
        root["items"] = [] as [Any]
        let empty = try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: root))
        let event = try #require(GrowthEvent.items(between: empty, after).first)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])
        func decode(_ segment: Any?) throws -> GrowthEvent {
            var copy = object
            copy["segment"] = segment
            return try JSONDecoder().decode(GrowthEvent.self, from: JSONSerialization.data(withJSONObject: copy))
        }
        let largest = Int.max / ItemDrop.stepsPerSegment
        #expect(try decode(largest).body.isEmpty == false)
        for bad in [nil, 0, -1, largest + 1, Int.max] as [Any?] {
            #expect(throws: DecodingError.self) { try decode(bad) }
        }
    }

    @Test func olderVersionsAreAcceptedWithoutItemsAndRejectedWithThem() throws {
        let state = try withItems()
        #expect(snapshot(state, version: 2, items: nil).supersedes(nil))
        #expect(!snapshot(state, version: 2, items: state.itemSummaries).supersedes(nil))
        #expect(snapshot(state, version: 1, dex: false, items: nil).supersedes(nil))
        #expect(!snapshot(state, version: 1, dex: false, items: state.itemSummaries).supersedes(nil))
        #expect(!snapshot(state, version: 4, items: state.itemSummaries).supersedes(nil))
    }

    @Test func sameRevisionUpgradeOnlyGoesUpInSchema() throws {
        let state = try withItems()
        let v2 = snapshot(state, version: 2, items: nil)
        let v3 = snapshot(state, version: 3, items: state.itemSummaries)
        #expect(v3.supersedes(v2))
        #expect(!v2.supersedes(v3))
        #expect(!v3.supersedes(v3))
        // A lower revision never wins, whatever its schema.
        let older = MonsterSnapshot(schemaVersion: 3, revision: state.revision - 1, createdAt: state.createdAt,
                                    monster: state.monster, todaySteps: nil, observedAt: nil, timeZone: .gmt,
                                    dex: state.dex, items: state.itemSummaries)
        #expect(!older.supersedes(v2))
        #expect(!older.supersedes(v3))
    }

    @Test func storedV1AndV2JsonStillDecodeAndV3ReplacesThem() throws {
        let v1 = try JSONDecoder().decode(MonsterSnapshot.self, from: Data(LegacyFixtures.snapshotV1.utf8))
        let v2 = try JSONDecoder().decode(MonsterSnapshot.self, from: Data(LegacyFixtures.gabuPunimonSnapshotV2.utf8))
        #expect(v1.items == nil && v2.items == nil)
        #expect(v1.supersedes(nil) && v2.supersedes(nil))
        var state = try LegacyFixtures.gameState(LegacyFixtures.gabuPunimonState)
        var generator = SeededGenerator(seed: 1)
        state.migrateToEvolutionCatalog(at: start, using: &generator)
        let v3 = state.snapshot
        #expect(v3.schemaVersion == MonsterSnapshot.currentSchemaVersion)
        #expect(v3.monster.id == v2.monster.id)
        #expect(v3.revision >= v2.revision)
        #expect(v3.supersedes(v2))
    }

    @Test func itemEventsListOnlyNewGrantsOldestFirst() throws {
        let after = try withItems()
        #expect(GrowthEvent.items(between: after, after).isEmpty)
        // Rebuild "before" with only the first grant.
        var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(after)) as? [String: Any])
        let all = try #require(root["items"] as? [[String: Any]])
        root["items"] = [all[0]]
        let partial = try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: root))
        let events = GrowthEvent.items(between: partial, after)
        #expect(events.count == after.items.count - 1)
        #expect(events.allSatisfy { $0.kind == .itemFound })
        #expect(events.compactMap(\.segment) == after.items.dropFirst().map(\.segment))
        let first = try #require(events.first)
        let grant = after.items[1]
        #expect(first.id == "\(after.monster.id.uuidString)-item-\(grant.segment)")
        #expect(first.itemId == grant.itemId)
        let name = try #require(ItemCatalog.info(id: grant.itemId)).name
        #expect(first.title == "\(name)\(KoreanParticle.object(name)) 얻었어요!")
        // Fixed text with the segment's step count (no species name, no locale-dependent separator).
        let thousands = ["1": "5,000", "2": "10,000", "3": "15,000", "4": "20,000", "5": "25,000", "6": "30,000",
                         "7": "35,000", "8": "40,000"]
        #expect(first.body == "누적 \(try #require(thousands["\(grant.segment)"]))걸음을 넘겨 찾았어요")
        #expect(!first.body.contains(after.monster.name) && !first.title.contains(after.monster.name))
        #expect(Set(events.map(\.id)).count == events.count)
        // Another partner generation yields nothing.
        #expect(GrowthEvent.items(between: GameState.fixedEgg(now: start, id: testPartnerId(88)), after).isEmpty)
        #expect(GrowthEvent.between(partial, after)?.kind != .itemFound)
    }

    @Test func itemEventSurvivesTheUndeliveredQueueAndOldQueueFilesStillDecode() throws {
        let after = try withItems()
        var root = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(after)) as? [String: Any])
        root["items"] = [] as [Any]
        let empty = try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: root))
        let event = try #require(GrowthEvent.items(between: empty, after).first)
        let decoded = try JSONDecoder().decode([GrowthEvent].self, from: JSONEncoder().encode([event]))
        #expect(decoded == [event] && decoded.first?.title == event.title)
    }

    @Test func queueFileWrittenBeforeItemsStillDecodes() throws {
        var state = GameState.fixedEgg(now: start)
        state.enroll(at: start)
        var generator = SeededGenerator(seed: 7)
        var next = state
        next.settle(day: start, steps: 600, distance: nil, at: start, using: &generator)
        let event = try #require(GrowthEvent.between(state, next))
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])
        object["itemId"] = nil
        object["segment"] = nil
        let decoded = try JSONDecoder().decode(GrowthEvent.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded == event && decoded.kind == .hatched && decoded.itemId == nil && decoded.segment == nil)
    }

    @Test func withParticle() {
        #expect(KoreanParticle.with("디지몬") == "과")
        #expect(KoreanParticle.with("아구몬") == "과")
        #expect(KoreanParticle.with("가부몬") == "과")
        #expect(KoreanParticle.with("테리어몬") == "과")
        #expect(KoreanParticle.with("파피") == "와")
        #expect(KoreanParticle.with("Agu") == "와(과)")
    }
}
