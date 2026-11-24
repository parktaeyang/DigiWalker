import DigiWalkerCore
import Foundation
import Testing
@testable import DigiWalker

@MainActor
struct DexModelTests {
    /// Builds a snapshot from JSON so the test does not depend on private initializers.
    private func snapshot(species: String, name: String, card: String?, dex: [String]?, version: Int = 2) throws -> MonsterSnapshot {
        let cardPart = card.map { #","cardId":"\#($0)""# } ?? ""
        let dexPart = dex.map {
            #","dex":["# + $0.map { #"{"speciesId":"\#($0)","firstMetAt":821692800,"firstMetSteps":0}"# }.joined(separator: ",") + "]"
        } ?? ""
        let json = #"{"schemaVersion":\#(version),"revision":1,"createdAt":821692800,"monster":{"id":"7770E692-324B-4A27-90EA-437743B4195A","speciesId":"\#(species)","name":"\#(name)","experience":0,"totalCreditedSteps":0,"distanceMeters":0\#(cardPart)},"timeZone":{"identifier":"GMT"}\#(dexPart)}"#
        return try JSONDecoder().decode(MonsterSnapshot.self, from: Data(json.utf8))
    }

    private func rows(_ model: DexModel) -> [DexModel.Row] { model.sections.flatMap(\.rows) }

    @Test func eggOnlyIsOneOfFifty() throws {
        let model = DexModel(snapshot: try snapshot(species: "digitama", name: "디지타마", card: nil, dex: ["digitama"]))
        #expect(model.synced)
        #expect(model.discoveredCount == 1)
        #expect(model.totalCount == 50)
        #expect(rows(model).count == 50)
        #expect(model.sections.map(\.title) == ["공통", "아구몬 카드", "파피몬 카드", "길몬 카드"])
    }

    @Test func sharedSpeciesAppearOnce() throws {
        let model = DexModel(snapshot: try snapshot(species: "digitama", name: "디지타마", card: nil, dex: ["digitama"]))
        let ids = rows(model).map(\.speciesId)
        #expect(Set(ids).count == ids.count)
        #expect(ids.filter { $0 == "algomon_adult" }.count == 1)
        #expect(ids.filter { $0 == "omegamon" }.count == 1)
        let agu = try #require(model.sections.first { $0.title == "아구몬 카드" })
        #expect(agu.rows.contains { $0.speciesId == "omegamon" && $0.alsoIn != nil })
    }

    @Test func metPoyomonAddsLegacySectionAndRaisesTotal() throws {
        let model = DexModel(snapshot: try snapshot(species: "koromon", name: "코로몬", card: "agu_ex",
                                                    dex: ["digitama", "poyomon", "botamon", "koromon"]))
        #expect(model.totalCount == 51)
        #expect(model.discoveredCount == 4)
        #expect(model.sections.last?.title == "이전 파트너")
        #expect(model.sections.last?.rows.map(\.speciesId) == ["poyomon"])
        #expect(model.sections.last?.rows.first?.stage == 0)
    }

    @Test func undiscoveredRowsHideTheName() throws {
        let model = DexModel(snapshot: try snapshot(species: "digitama", name: "디지타마", card: nil, dex: ["digitama"]))
        let omega = try #require(rows(model).first { $0.speciesId == "omegamon" })
        #expect(!omega.discovered)
        #expect(omega.displayName == "???")
        #expect(rows(model).filter { !$0.discovered }.allSatisfy { $0.displayName == "???" })
        let egg = try #require(rows(model).first { $0.speciesId == "digitama" })
        #expect(egg.displayName == "디지타마")
    }

    @Test func v1SnapshotShowsOnlyTheCurrentPartner() throws {
        let known = DexModel(snapshot: try snapshot(species: "botamon", name: "깜몬", card: nil, dex: nil, version: 1))
        #expect(!known.synced)
        #expect(rows(known).map(\.speciesId) == ["botamon"])
        #expect(rows(known).first?.displayName == "깜몬")
        let outside = DexModel(snapshot: try snapshot(species: "starter_acorn", name: "도토롱", card: nil, dex: nil, version: 1))
        #expect(rows(outside).map(\.speciesId) == ["starter_acorn"])
        #expect(rows(outside).first?.displayName == "도토롱")
        #expect(outside.discoveredCount == 0)
        #expect(outside.totalCount == 50)
    }

    @Test func unknownSpeciesInSyncedDexGoesToFormerPartners() throws {
        let model = DexModel(snapshot: try snapshot(species: "mystery", name: "???몬", card: nil, dex: ["digitama", "mystery"]))
        let former = try #require(model.sections.first { $0.title == "이전 파트너" })
        #expect(former.rows.map(\.speciesId) == ["mystery"])
        #expect(former.rows.first?.displayName == "???몬")
        #expect(model.discoveredCount == 1)
        #expect(model.totalCount == 50)
    }

    @Test func v1BabyKeepsTheBabyStage() throws {
        let model = DexModel(snapshot: try snapshot(species: "punimon", name: "푸니몬", card: nil, dex: nil, version: 1))
        #expect(rows(model).first?.stage == 0)
    }

    @Test func restoredCacheMustPassSnapshotValidation() throws {
        let valid = PhoneCache(snapshot: try snapshot(species: "digitama", name: "디지타마", card: nil, dex: ["digitama"]), receivedAt: .now)
        let invalid = PhoneCache(snapshot: try snapshot(species: "koromon", name: "코로몬", card: "agu_ex", dex: ["digitama"]), receivedAt: .now)
        #expect(PhoneSyncService.validated(valid) != nil)
        #expect(PhoneSyncService.validated(invalid) == nil) // current species missing from dex
        #expect(PhoneSyncService.validated(nil) == nil)
    }
}
