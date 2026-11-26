import DigiWalkerCore
import Foundation
import Testing
@testable import DigiWalker

@MainActor
struct ItemModelTests {
    /// A v3 (or older) snapshot built from JSON, so the test does not depend on private initializers.
    private func snapshot(items: [(id: String, count: Int)]?, version: Int = 3, steps: Int = 75_000) throws -> MonsterSnapshot {
        let itemPart = items.map {
            #","items":["# + $0.map {
                #"{"itemId":"\#($0.id)","count":\#($0.count),"firstGrantedAt":821692800,"currentPartnerCount":\#($0.count)}"#
            }.joined(separator: ",") + "]"
        } ?? ""
        let json = #"{"schemaVersion":\#(version),"revision":1,"createdAt":821692800,"monster":{"id":"7770E692-324B-4A27-90EA-437743B4195A","speciesId":"digitama","name":"디지타마","experience":0,"totalCreditedSteps":\#(steps),"distanceMeters":0},"timeZone":{"identifier":"GMT"},"dex":[{"speciesId":"digitama","firstMetAt":821692800,"firstMetSteps":0}]\#(itemPart)}"#
        return try JSONDecoder().decode(MonsterSnapshot.self, from: Data(json.utf8))
    }

    @Test func v2CacheHasNoItemsAndSaysSo() throws {
        let model = ItemModel(snapshot: try snapshot(items: nil, version: 2))
        #expect(!model.synced)
        #expect(model.ownedKinds == 0 && model.totalKinds == 25)
        #expect(model.sections.flatMap(\.rows).allSatisfy { !$0.owned })
    }

    @Test func v3ShowsAllTwentyFiveWithOwnedCounts() throws {
        let shot = try snapshot(items: [("digicore", 3), ("crest_courage", 1), ("future_item", 9)])
        #expect(shot.supersedes(nil))
        let model = ItemModel(snapshot: shot)
        #expect(model.synced)
        #expect(model.sections.map(\.title) == ["문장", "디지멘탈", "기타"])
        #expect(model.sections.map(\.rows.count) == [11, 11, 3])
        let rows = model.sections.flatMap(\.rows)
        #expect(rows.count == 25)
        #expect(model.ownedKinds == 2) // the unknown id is not a catalog item
        #expect(rows.first { $0.id == "digicore" }?.count == 3)
        #expect(rows.first { $0.id == "crest_courage" }?.owned == true)
        #expect(rows.first { $0.id == "crest_love" }?.owned == false)
        // Only the four items that gate an evolution say so.
        #expect(Set(rows.filter(\.unlocksEvolution).map(\.id)) == ["digicore", "digicode", "digimental_fate", "x_antibody"])
    }

    @Test func emptyV3ListIsSyncedWithNothingOwned() throws {
        let model = ItemModel(snapshot: try snapshot(items: []))
        #expect(model.synced && model.ownedKinds == 0)
    }

    @Test func dexShowsTheRequiredItemOnLockedSpecies() throws {
        let owned = DexModel(snapshot: try snapshot(items: [("digimental_fate", 1)]))
        let missing = DexModel(snapshot: try snapshot(items: []))
        let old = DexModel(snapshot: try snapshot(items: nil, version: 2))
        func row(_ model: DexModel, _ id: String) throws -> DexModel.Row {
            try #require(model.sections.flatMap(\.rows).first { $0.speciesId == id })
        }
        #expect(try row(owned, "rapidmon_armor").requiredItem?.id == "digimental_fate")
        #expect(try row(owned, "rapidmon_armor").requiredItemOwned == true)
        #expect(try row(missing, "rapidmon_armor").requiredItemOwned == false)
        #expect(try row(old, "rapidmon_armor").requiredItem?.id == "digimental_fate")
        #expect(try row(old, "rapidmon_armor").requiredItemOwned == nil)
        #expect(try row(owned, "agumon").requiredItem == nil)
        // Every locked species of the catalog shows an item.
        let locked = owned.sections.flatMap(\.rows).filter { $0.requiredItem != nil }
        #expect(Set(locked.map(\.speciesId)) == ["donedevimon", "rapidmon_armor", "sakuyamon_x", "lordknightmon",
                                                  "dynasmon", "murmukusmon", "lucemon_falldown"])
    }
}
