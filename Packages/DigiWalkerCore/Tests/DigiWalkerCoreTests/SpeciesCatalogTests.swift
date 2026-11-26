import Testing
@testable import DigiWalkerCore

@Suite struct SpeciesCatalogTests {
    @Test func speciesIdsAreUnique() {
        let ids = SpeciesCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.count == 185)
    }

    @Test func cardsHaveSixStagesAndSeventeenUniqueSlots() {
        #expect(SpeciesCatalog.cards.map(\.id) == [
            "agu_ex", "gabu_ex", "guil_ex", "terrier_ex", "rena_ex", "agni_ex",
            "fairi_ex", "chack_ex", "wolf_ex", "blitz_ex", "louwe_ex",
        ])
        #expect(Set(SpeciesCatalog.cards.map(\.id)).count == 11)
        #expect(Set(SpeciesCatalog.cards.map(\.catalogCardId)).count == 11)
        #expect(Set(SpeciesCatalog.cards.map(\.dimId)).count == 11)
        for card in SpeciesCatalog.cards {
            #expect(card.stages.count == 6)
            let slots = card.stages.flatMap { $0 }
            #expect(slots.count == 17)
            #expect(Set(slots.map(\.speciesId)).count == 17)
            #expect(Set(slots.map(\.dimIndex)) == Set(0..<17))
            // Stage 0 and 1 are always one species; Frontier cards have two at stage 2.
            #expect(card.stages.prefix(2).allSatisfy { $0.count == 1 })
            #expect(card.stages[2].count == 1 || card.stages[2].count == 2)
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

    @Test func sharedSpeciesAreExactlyTheKnownFour() {
        var counts: [String: Int] = [:]
        var stages: [String: Set<Int>] = [:]
        for card in SpeciesCatalog.cards {
            for (stage, slots) in card.stages.enumerated() {
                for slot in slots {
                    counts[slot.speciesId, default: 0] += 1
                    stages[slot.speciesId, default: []].insert(stage)
                }
            }
        }
        let shared = Set(counts.filter { $0.value > 1 }.keys)
        #expect(shared == ["algomon_adult", "omegamon", "botamon", "susanoomon"])
        // A shared species sits at the same stage in every card, so its sprite spec is unambiguous.
        for id in shared { #expect(stages[id]?.count == 1) }
        #expect(counts.count == 183)
        #expect(SpeciesCatalog.cardSpeciesIds.count == 183)
        #expect(Set(SpeciesCatalog.cardSpeciesIds).count == 183)
    }

    @Test func sharedSpeciesBaseCardsAndCardLookup() {
        #expect(SpeciesCatalog.cards.first?.id == "agu_ex")
        #expect(EvolutionCard.cards(containing: "botamon").map(\.id) == ["agu_ex", "wolf_ex"])
        #expect(EvolutionCard.cards(containing: "susanoomon").map(\.id) == ["agni_ex", "wolf_ex"])
        #expect(EvolutionCard.cards(containing: "algomon_adult").map(\.id) == ["agu_ex", "gabu_ex"])
        #expect(EvolutionCard.cards(containing: "omegamon").map(\.id) == ["agu_ex", "gabu_ex"])
        #expect(EvolutionCard.cards(containing: "zerimon").map(\.id) == ["terrier_ex"])
        #expect(EvolutionCard.cards(containing: "digitama").isEmpty)
        // Every species is listed under every card that holds it.
        for id in SpeciesCatalog.cardSpeciesIds { #expect(!EvolutionCard.cards(containing: id).isEmpty) }
    }

    @Test func dexUniverseSize() {
        #expect(SpeciesCatalog.dexUniverse(includingLegacy: false).count == 184)
        #expect(SpeciesCatalog.dexUniverse(includingLegacy: true).count == 185)
    }

    @Test func jogressOnlySpeciesSetIsExactlyOmegamonAndSusanoomon() {
        #expect(SpeciesCatalog.jogressOnlySpeciesIds == ["omegamon", "susanoomon"])
    }

    @Test func onlyJogressSpeciesAreExcludedFromRandomPicks() {
        let jogress: Set<String> = ["omegamon", "susanoomon"]
        for card in SpeciesCatalog.cards {
            for (stage, slots) in card.stages.enumerated() {
                #expect(!card.eligible(stage: stage).isEmpty)
                for slot in slots { #expect(slot.randomEligible == !jogress.contains(slot.speciesId)) }
            }
        }
    }

    @Test func unlockRequiredSpeciesNeedTheirItemForRandomEvolution() throws {
        let locked: [String: String] = [
            "donedevimon": "digicore", "rapidmon_armor": "digimental_fate", "sakuyamon_x": "x_antibody",
            "lordknightmon": "digicore", "dynasmon": "digicore", "murmukusmon": "digicode",
            "lucemon_falldown": "digicode",
        ]
        var found = Set<String>()
        for card in SpeciesCatalog.cards {
            for (stage, slots) in card.stages.enumerated() {
                for slot in slots {
                    #expect(slot.requiredItemId == locked[slot.speciesId], "\(slot.speciesId)")
                    guard let item = slot.requiredItemId else { continue }
                    found.insert(slot.speciesId)
                    #expect(ItemCatalog.info(id: item) != nil)
                    #expect(!card.eligible(stage: stage, owning: []).map(\.speciesId).contains(slot.speciesId))
                    #expect(card.eligible(stage: stage, owning: [item]).map(\.speciesId).contains(slot.speciesId))
                    #expect(card.eligible(stage: stage, owning: ["crest_courage"]).map(\.speciesId)
                        .contains(slot.speciesId) == false)
                }
                // The gate never empties a stage, with no items or with all of them.
                #expect(!card.eligible(stage: stage, owning: []).isEmpty, "\(card.id) \(stage)")
                #expect(card.eligible(stage: stage, owning: Set(ItemCatalog.ids)) == card.eligible(stage: stage))
            }
        }
        #expect(found == Set(locked.keys))
    }
    @Test func koreanNamesForNewCardsAreMarkedUnverified() throws {
        let old: Set<String> = Set(
            [EvolutionCard.agumonEX, .gabumonEX, .guilmonEX].flatMap { $0.stages.flatMap { $0.map(\.speciesId) } })
        for id in SpeciesCatalog.cardSpeciesIds where !old.contains(id) {
            let info = try #require(SpeciesCatalog.info(id: id))
            #expect(!info.nameVerified, "\(id)")
            #expect(!info.name.isEmpty && !info.englishName.isEmpty)
        }
        #expect(SpeciesCatalog.info(id: "botamon")?.nameVerified == true)
    }

    @Test func requiredStepsHatchAt500ThenGrowByFiveThousandEachStage() {
        #expect((0..<6).map(EvolutionCard.requiredSteps(stage:)) == [500, 5_000, 15_000, 30_000, 50_000, 75_000])
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
