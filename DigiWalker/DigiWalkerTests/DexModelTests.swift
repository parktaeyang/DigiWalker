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

    private var cardTitleList: [String] { SpeciesCatalog.cards.map { DexModel.cardTitles[$0.id] ?? "" } }

    @Test func everyCardHasAKoreanTitle() {
        for card in SpeciesCatalog.cards {
            let title = DexModel.cardTitles[card.id]
            #expect(title?.isEmpty == false, "missing title for \(card.id)")
            #expect(title != card.displayName)
        }
        #expect(Set(cardTitleList).count == SpeciesCatalog.cards.count)
    }

    @Test func eggOnlyCountsUniqueSpeciesOnce() throws {
        let model = DexModel(snapshot: try snapshot(species: "digitama", name: "디지타마", card: nil, dex: ["digitama"]))
        #expect(model.synced)
        #expect(model.discoveredCount == 1)
        #expect(model.totalCount == 184)
        #expect(model.totalCount == 1 + SpeciesCatalog.cardSpeciesIds.count)
        // Rows are per card section, so shared species add rows but not to the species count.
        let shown = rows(model).count
        #expect(shown == 1 + SpeciesCatalog.cards.reduce(0) { $0 + $1.stages.reduce(0) { $0 + $1.count } })
        #expect(shown == 1 + 11 * 17)
        #expect(Set(rows(model).map(\.speciesId)).count == 184)
        #expect(model.sections.map(\.title) == ["공통"] + cardTitleList)
    }

    @Test func sharedSpeciesAppearInEveryCardSection() throws {
        let model = DexModel(snapshot: try snapshot(species: "digitama", name: "디지타마", card: nil, dex: ["digitama"]))
        func section(_ card: String) throws -> DexModel.Section {
            try #require(model.sections.first { $0.title == DexModel.cardTitles[card] })
        }
        for (species, cards) in [("botamon", ["agu_ex", "wolf_ex"]), ("susanoomon", ["agni_ex", "wolf_ex"]),
                                 ("algomon_adult", ["agu_ex", "gabu_ex"]), ("omegamon", ["agu_ex", "gabu_ex"])] {
            for card in SpeciesCatalog.cards.map(\.id) {
                let count = try section(card).rows.filter { $0.speciesId == species }.count
                #expect(count == (cards.contains(card) ? 1 : 0), "\(species) in \(card)")
            }
        }
        // Rows inside one section never repeat a species.
        for section in model.sections { #expect(Set(section.rows.map(\.speciesId)).count == section.rows.count) }
    }

    @Test func discoveringASharedSpeciesOpensBothSections() throws {
        let model = DexModel(snapshot: try snapshot(species: "wanyamon", name: "와냐몬", card: "wolf_ex",
                                                    dex: ["digitama", "botamon", "wanyamon"]))
        #expect(model.discoveredCount == 3)
        #expect(model.totalCount == 184)
        for card in ["agu_ex", "wolf_ex"] {
            let section = try #require(model.sections.first { $0.title == DexModel.cardTitles[card] })
            let botamon = try #require(section.rows.first { $0.speciesId == "botamon" })
            #expect(botamon.discovered)
            #expect(botamon.stage == 0)
        }
        let wolf = try #require(model.sections.first { $0.title == "울프몬 카드" })
        #expect(wolf.rows.first { $0.speciesId == "wanyamon" }?.discovered == true)
        #expect(wolf.rows.count == 17)
    }

    @Test func jogressOnlySpeciesAreDerivedFromTheCards() {
        #expect(DexModel.isJogressOnly("omegamon"))
        #expect(DexModel.isJogressOnly("susanoomon"))
        #expect(!DexModel.isJogressOnly("wargreymon"))
        #expect(!DexModel.isJogressOnly("algomon_adult"))
        #expect(!DexModel.isJogressOnly("digitama"))
        let expected = Set(SpeciesCatalog.cardSpeciesIds.filter { id in
            EvolutionCard.cards(containing: id).allSatisfy { $0.slot(of: id)?.randomEligible == false }
        })
        #expect(expected == ["omegamon", "susanoomon"])
    }

    @Test func undiscoveredJogressRowsAreFlagged() throws {
        let model = DexModel(snapshot: try snapshot(species: "digitama", name: "디지타마", card: nil, dex: ["digitama"]))
        let flagged = Set(rows(model).filter(\.jogressOnly).map(\.speciesId))
        #expect(flagged == ["omegamon", "susanoomon"])
    }

    @Test func metPoyomonAddsLegacySectionAndRaisesTotal() throws {
        let model = DexModel(snapshot: try snapshot(species: "koromon", name: "코로몬", card: "agu_ex",
                                                    dex: ["digitama", "poyomon", "botamon", "koromon"]))
        #expect(model.totalCount == 185)
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
        #expect(outside.totalCount == 184)
    }

    @Test func unknownSpeciesInSyncedDexGoesToFormerPartners() throws {
        let model = DexModel(snapshot: try snapshot(species: "mystery", name: "???몬", card: nil, dex: ["digitama", "mystery"]))
        let former = try #require(model.sections.first { $0.title == "이전 파트너" })
        #expect(former.rows.map(\.speciesId) == ["mystery"])
        #expect(former.rows.first?.displayName == "???몬")
        #expect(model.discoveredCount == 1)
        #expect(model.totalCount == 184)
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
