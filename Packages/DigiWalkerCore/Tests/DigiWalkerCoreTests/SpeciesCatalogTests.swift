import Testing
@testable import DigiWalkerCore

@Suite struct SpeciesCatalogTests {
    @Test func speciesIdsAreUnique() {
        let ids = SpeciesCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.count == 51)
    }

    @Test func cardsHaveSixStagesAndSeventeenUniqueSlots() {
        #expect(SpeciesCatalog.cards.map(\.id) == ["agu_ex", "gabu_ex", "guil_ex"])
        for card in SpeciesCatalog.cards {
            #expect(card.stages.count == 6)
            let slots = card.stages.flatMap { $0 }
            #expect(slots.count == 17)
            #expect(Set(slots.map(\.speciesId)).count == 17)
            #expect(Set(slots.map(\.dimIndex)) == Set(0..<17))
            #expect(card.stages.prefix(3).allSatisfy { $0.count == 1 })
        }
    }

    @Test func everySlotSpeciesIsInCatalogWithMatchingSpec() throws {
        for card in SpeciesCatalog.cards {
            for (stage, slots) in card.stages.enumerated() {
                for slot in slots {
                    let info = try #require(SpeciesCatalog.info(id: slot.speciesId))
                    let spec = try #require(info.dimSprite)
                    if stage <= 1 {
                        #expect(spec == DIMSpriteSpec(frameWidth: 32, frameHeight: 24, frameCount: 5))
                    } else {
                        #expect(spec == DIMSpriteSpec(frameWidth: 64, frameHeight: 56, frameCount: 12))
                    }
                    #expect(spec.idleFrames.allSatisfy { (0..<spec.frameCount).contains($0) })
                }
            }
        }
    }

    @Test func sharedSpeciesAreExactlyAlgomonAndOmegamon() {
        var counts: [String: Int] = [:]
        for card in SpeciesCatalog.cards {
            for slot in card.stages.flatMap({ $0 }) { counts[slot.speciesId, default: 0] += 1 }
        }
        #expect(Set(counts.filter { $0.value > 1 }.keys) == ["algomon_adult", "omegamon"])
        #expect(counts.count == 49)
        #expect(SpeciesCatalog.cardSpeciesIds.count == 49)
    }

    @Test func dexUniverseSize() {
        #expect(SpeciesCatalog.dexUniverse(includingLegacy: false).count == 50)
        #expect(SpeciesCatalog.dexUniverse(includingLegacy: true).count == 51)
    }

    @Test func onlyOmegamonIsExcludedFromRandomPicks() {
        for card in SpeciesCatalog.cards {
            for (stage, slots) in card.stages.enumerated() {
                #expect(!card.eligible(stage: stage).isEmpty)
                for slot in slots { #expect(slot.randomEligible == (slot.speciesId != "omegamon")) }
            }
        }
    }

    @Test func requiredStepsHatchAt500ThenEvery5000() {
        #expect((0..<6).map(EvolutionCard.requiredSteps(stage:)) == [500, 10_000, 15_000, 20_000, 25_000, 30_000])
    }

    @Test func existingIdsAndPoyomonOutsideCards() throws {
        for id in ["digitama", "botamon", "punimon", "poyomon"] { #expect(SpeciesCatalog.info(id: id) != nil) }
        #expect(SpeciesCatalog.info(id: "digitama")?.dimSprite == nil)
        #expect(SpeciesCatalog.info(id: "poyomon")?.dimSprite == nil)
        #expect(SpeciesCatalog.cards.allSatisfy { $0.stage(of: "poyomon") == nil })
        #expect(SpeciesCatalog.info(id: "gabumon")?.name == "파피몬")
        #expect(SpeciesCatalog.card(id: "agu_ex")?.catalogCardId == "04c5dc576a34887b")
        #expect(SpeciesCatalog.card(id: "nope") == nil)
    }
}
