import Foundation

/// One character slot of a DIM card. `dimIndex` is the character index inside the card's sprite sheet set.
public struct CardSlot: Equatable, Sendable {
    public let speciesId: String
    public let dimIndex: Int
    /// False for species that random evolution must never pick (Omegamon is Jogress-only).
    public let randomEligible: Bool
    /// Item the partner must own before random evolution may pick this species (nil = no item needed).
    public let requiredItemId: String?

    public init(speciesId: String, dimIndex: Int, randomEligible: Bool = true, requiredItemId: String? = nil) {
        self.speciesId = speciesId
        self.dimIndex = dimIndex
        self.randomEligible = randomEligible
        self.requiredItemId = requiredItemId
    }
}

/// A DIM EX card used as a fixed evolution line. Stages 0...5 each list the species available at that stage.
public struct EvolutionCard: Equatable, Sendable {
    public static let stageCount = 6
    public static let stepsPerStage = 5_000
    /// The egg hatches sooner than the later stages (user request, 2026-11-25).
    public static let hatchSteps = 500

    public let id: String
    public let catalogCardId: String
    /// DIM id in the card header (catalog `dimId`); lets tools check that a BIN really is this card.
    public let dimId: Int
    public let displayName: String
    public let stages: [[CardSlot]]

    /// Cumulative credited steps needed to reach `stage`. The egg hatches at 500. After that each evolution needs
    /// 5,000 more steps than the previous one (user decision, 2026-11-26): 5,000, 15,000, 30,000, 50,000, 75,000.
    public static func requiredSteps(stage: Int) -> Int {
        stage == 0 ? hatchSteps : stepsPerStage * stage * (stage + 1) / 2
    }

    public func stage(of speciesId: String) -> Int? {
        stages.firstIndex { $0.contains { $0.speciesId == speciesId } }
    }

    public func slot(of speciesId: String) -> CardSlot? {
        stages.lazy.flatMap { $0 }.first { $0.speciesId == speciesId }
    }

    public func eligible(stage: Int) -> [CardSlot] {
        guard stages.indices.contains(stage) else { return [] }
        return stages[stage].filter(\.randomEligible)
    }

    /// Candidates for random evolution: item-locked species only count when their item is owned.
    public func eligible(stage: Int, owning items: Set<String>) -> [CardSlot] {
        eligible(stage: stage).filter { $0.requiredItemId.map(items.contains) ?? true }
    }

    /// Items that would unlock a species on this card, in card order, without duplicates.
    public var requiredItemIds: [String] {
        var seen = Set<String>()
        return stages.flatMap { $0 }.compactMap(\.requiredItemId).filter { seen.insert($0).inserted }
    }
}

extension EvolutionCard {
    private static func slot(_ id: String, _ index: Int, eligible: Bool = true, needs item: String? = nil) -> CardSlot {
        CardSlot(speciesId: id, dimIndex: index, randomEligible: eligible, requiredItemId: item)
    }

    // `needs:` marks the original unlock-required species; the item mapping is an app rule (2026-11-26).
    // Species slots come from the DIM Modifier catalog checked on 2026-11-25. Evolution links are an app rule
    // (random within the card), not the original chart.
    public static let agumonEX = EvolutionCard(
        id: "agu_ex", catalogCardId: "04c5dc576a34887b", dimId: 12, displayName: "Agumon EX",
        stages: [
            [slot("botamon", 0)],
            [slot("koromon", 1)],
            [slot("agumon", 2)],
            [slot("greymon", 3), slot("coelamon", 4), slot("ogremon", 5), slot("algomon_adult", 6)],
            [slot("metalgreymon_vaccine", 7), slot("andromon", 8), slot("anomalocarimon", 9),
             slot("mamemon", 10), slot("neodevimon", 11), slot("metaltyranomon", 12)],
            [slot("wargreymon", 13), slot("omegamon", 14, eligible: false), slot("blitzgreymon", 15),
             slot("donedevimon", 16, needs: "digicore")],
        ])

    public static let gabumonEX = EvolutionCard(
        id: "gabu_ex", catalogCardId: "5e133fc75fc90377", dimId: 13, displayName: "Gabumon EX",
        stages: [
            [slot("punimon", 0)],
            [slot("tsunomon", 1)],
            [slot("gabumon", 2)],
            [slot("garurumon", 3), slot("gorimon", 4), slot("dokugumon", 5), slot("algomon_adult", 6)],
            [slot("weregarurumon", 7), slot("parrotmon", 8), slot("valvemon", 9),
             slot("bigmamemon", 10), slot("orochimon", 11), slot("waruseadramon", 12)],
            [slot("metalgarurumon", 13), slot("omegamon", 14, eligible: false), slot("cresgarurumon", 15),
             slot("nidhoggmon", 16)],
        ])

    public static let guilmonEX = EvolutionCard(
        id: "guil_ex", catalogCardId: "23d5bc7093090fc5", dimId: 17, displayName: "Guilmon EX",
        stages: [
            [slot("jyarimon", 0)],
            [slot("gigimon", 1)],
            [slot("guilmon", 2)],
            [slot("siesamon", 3), slot("growmon_orange", 4), slot("growmon", 5), slot("devidramon", 6)],
            [slot("vajramon", 7), slot("majiramon", 8), slot("mihiramon", 9),
             slot("megalogrowmon_orange", 10), slot("megalogrowmon", 11), slot("sandiramon", 12)],
            [slot("dukemon", 13), slot("dukemon_x", 14), slot("megidramon", 15),
             slot("dukemon_crimson", 16)],
        ])

    // Cards 4-11 below were added on 2026-11-26 from the same catalog. Frontier cards have two stage-2 species.
    // Susanoomon is shared by Agnimon and Wolfmon and is Jogress-only, so random evolution skips it.
    public static let terriermonEX = EvolutionCard(
        id: "terrier_ex", catalogCardId: "b8a262b73a584fa2", dimId: 18, displayName: "Terriermon EX",
        stages: [
            [slot("zerimon", 0)],
            [slot("gummymon", 1)],
            [slot("terriermon", 2)],
            [slot("galgomon", 3), slot("turuiemon", 4), slot("harpymon", 5), slot("wendimon", 6)],
            [slot("rapidmon", 7), slot("sinduramon", 8), slot("makuramon", 9),
             slot("andiramon_deva", 10), slot("pajiramon", 11), slot("andiramon", 12)],
            [slot("saintgalgomon", 13), slot("cherubimon_virtue", 14), slot("cherubimon_vice", 15),
             slot("rapidmon_armor", 16, needs: "digimental_fate")],
        ])

    public static let renamonEX = EvolutionCard(
        id: "rena_ex", catalogCardId: "ebec1fb5584f9ccc", dimId: 32, displayName: "Renamon EX",
        stages: [
            [slot("relemon", 0)],
            [slot("pokomon", 1)],
            [slot("renamon", 2)],
            [slot("kyubimon", 3), slot("youkomon", 4), slot("icedevimon", 5), slot("lynxmon", 6)],
            [slot("kumbhiramon", 7), slot("vikaralamon", 8), slot("taomon", 9),
             slot("doumon", 10), slot("caturamon", 11), slot("indaramon", 12)],
            [slot("sakuyamon", 13), slot("parasimon", 14), slot("kuzuhamon_miko", 15),
             slot("sakuyamon_x", 16, needs: "x_antibody")],
        ])

    public static let agnimonEX = EvolutionCard(
        id: "agni_ex", catalogCardId: "ffffde3475e68d8e", dimId: 6, displayName: "Agnimon EX",
        stages: [
            [slot("mokumon", 0)],
            [slot("petimeramon", 1)],
            [slot("flamon", 2), slot("gottsumon", 3)],
            [slot("agnimon", 4), slot("meramon", 5), slot("starmon", 6), slot("grottemon", 7)],
            [slot("aldamon", 8), slot("vritramon", 9), slot("superstarmon", 10),
             slot("gigasmon", 11), slot("darksuperstarmon", 12)],
            [slot("kaisergreymon", 13), slot("ancientgreymon", 14), slot("ancientvolcamon", 15),
             slot("susanoomon", 16, eligible: false)],
        ])

    public static let fairimonEX = EvolutionCard(
        id: "fairi_ex", catalogCardId: "ad95fda80f528ee8", dimId: 10, displayName: "Fairimon EX",
        stages: [
            [slot("yuramon", 0)],
            [slot("tanemon", 1)],
            [slot("tinkermon", 2), slot("pomumon", 3)],
            [slot("fairimon", 4), slot("cockatrimon", 5), slot("arbormon", 6), slot("zassoumon", 7)],
            [slot("jetsilphymon", 8), slot("shutumon", 9), slot("petaldramon", 10),
             slot("peacockmon", 11), slot("zamielmon", 12)],
            [slot("ancientirismon", 13), slot("lotusmon", 14), slot("ancienttroiamon", 15),
             slot("lordknightmon", 16, needs: "digicore")],
        ])

    public static let chackmonEX = EvolutionCard(
        id: "chack_ex", catalogCardId: "8160a04f17b7e759", dimId: 16, displayName: "Chackmon EX",
        stages: [
            [slot("yukimibotamon", 0)],
            [slot("hiyarimon", 1)],
            [slot("bearmon", 2), slot("snowgoblimon", 3)],
            [slot("chackmon", 4), slot("gryzmon", 5), slot("icemon", 6), slot("mojyamon", 7)],
            [slot("daipenmon", 8), slot("blizzarmon", 9), slot("panjyamon_x", 10),
             slot("nanomon", 11), slot("astamon", 12)],
            [slot("olegmon", 13), slot("frosvelgrmon", 14), slot("ancientmegatheriumon", 15),
             slot("dynasmon", 16, needs: "digicore")],
        ])

    public static let wolfmonEX = EvolutionCard(
        id: "wolf_ex", catalogCardId: "2661974b34f571f5", dimId: 36, displayName: "Wolfmon EX",
        stages: [
            [slot("botamon", 0)],
            [slot("wanyamon", 1)],
            [slot("strabimon", 2), slot("gizamon", 3)],
            [slot("wolfmon", 4), slot("dobermon", 5), slot("ranamon", 6), slot("ebidramon", 7)],
            [slot("beowolfmon", 8), slot("garummon", 9), slot("calamaramon", 10),
             slot("sirenmon", 11), slot("splashmon", 12)],
            [slot("magnagarurumon", 13), slot("ancientgarurumon", 14), slot("ancientmermaimon", 15),
             slot("susanoomon", 16, eligible: false)],
        ])

    public static let blitzmonEX = EvolutionCard(
        id: "blitz_ex", catalogCardId: "a5735c0f13f86ae3", dimId: 37, displayName: "Blitzmon EX",
        stages: [
            [slot("choromon", 0)],
            [slot("caprimon", 1)],
            [slot("kokabuterimon", 2), slot("kokuwamon", 3)],
            [slot("blitzmon", 4), slot("thunderballmon", 5), slot("mercuremon", 6),
             slot("bladekuwagamon", 7)],
            [slot("rhinokabuterimon", 8), slot("bolgmon", 9), slot("sephirothmon", 10),
             slot("metallifekuwagamon", 11), slot("wisemon", 12)],
            [slot("ancientbeatmon", 13), slot("grandiskuwagamon", 14), slot("ancientwisemon", 15),
             slot("murmukusmon", 16, needs: "digicode")],
        ])

    public static let louwemonEX = EvolutionCard(
        id: "louwe_ex", catalogCardId: "10ab04bac23563d0", dimId: 33, displayName: "Louwemon EX",
        stages: [
            [slot("popomon", 0)],
            [slot("frimon", 1)],
            [slot("liollmon", 2), slot("gazimon", 3)],
            [slot("louwemon", 4), slot("liamon", 5), slot("duskmon", 6), slot("madleomon", 7)],
            [slot("raihimon", 8), slot("kaiserleomon", 9), slot("loaderleomon", 10),
             slot("velgrmon", 11), slot("skullsatamon", 12), slot("lucemon_falldown", 13, needs: "digicode")],
            [slot("deathmon", 14), slot("dinotigermon", 15), slot("ancientsphinxmon", 16)],
        ])

    /// Every card that lists `speciesId` (shared species appear in more than one card), in card order.
    public static func cards(containing speciesId: String) -> [EvolutionCard] {
        SpeciesCatalog.cards.filter { $0.stage(of: speciesId) != nil }
    }
}
