import Foundation

/// One character slot of a DIM card. `dimIndex` is the character index inside the card's sprite sheet set.
public struct CardSlot: Equatable, Sendable {
    public let speciesId: String
    public let dimIndex: Int
    /// False for species that random evolution must never pick (Omegamon is Jogress-only).
    public let randomEligible: Bool

    public init(speciesId: String, dimIndex: Int, randomEligible: Bool = true) {
        self.speciesId = speciesId
        self.dimIndex = dimIndex
        self.randomEligible = randomEligible
    }
}

/// A DIM EX card used as a fixed evolution line. Stages 0...5 each list the species available at that stage.
public struct EvolutionCard: Equatable, Sendable {
    public static let stageCount = 6
    public static let stepsPerStage = 5_000

    public let id: String
    public let catalogCardId: String
    /// DIM id in the card header (catalog `dimId`); lets tools check that a BIN really is this card.
    public let dimId: Int
    public let displayName: String
    public let stages: [[CardSlot]]

    /// Credited steps needed to reach `stage` (stage 0 hatches at 5,000, stage 5 at 30,000).
    public static func requiredSteps(stage: Int) -> Int { stepsPerStage * (stage + 1) }

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
}

extension EvolutionCard {
    private static func slot(_ id: String, _ index: Int, eligible: Bool = true) -> CardSlot {
        CardSlot(speciesId: id, dimIndex: index, randomEligible: eligible)
    }

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
             slot("donedevimon", 16)],
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
}
