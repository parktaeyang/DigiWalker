import Foundation

public struct BattleFighter: Equatable, Sendable {
    public let speciesId: String
    public let name: String
    public let stage: Int

    public init(speciesId: String, name: String, stage: Int) {
        self.speciesId = speciesId
        self.name = name
        self.stage = stage
    }
}

/// Who can fight, from the cached snapshot (dex + current partner). Read only.
public struct BattleRoster: Equatable, Sendable {
    /// The current partner is still an egg: battles are not possible at all (user decision 2026-11-28).
    public let isBlockedByEgg: Bool
    /// The current partner when it has a battle stage; nil for eggs and legacy Poyomon.
    public let defaultFighter: BattleFighter?
    private let fighters: [BattleFighter]

    public init(snapshot: MonsterSnapshot) {
        let monster = snapshot.monster
        isBlockedByEgg = monster.isEgg
        var ids = Set((snapshot.dex ?? []).map(\.speciesId))
        ids.insert(monster.speciesId)

        func fighter(_ id: String) -> BattleFighter? {
            guard let stage = SpeciesCatalog.battleStage(of: id) else { return nil }
            let name = SpeciesCatalog.info(id: id)?.name ?? (id == monster.speciesId ? monster.name : nil)
            return name.map { BattleFighter(speciesId: id, name: $0, stage: stage) }
        }
        defaultFighter = fighter(monster.speciesId)
        // Discovery-list order (same as the dex); shared species appear once. Species without a stage never qualify.
        fighters = SpeciesCatalog.cardSpeciesIds.filter(ids.contains).compactMap(fighter)
    }

    /// Stages that have at least one fighter, ascending.
    public var stages: [Int] { Array(Set(fighters.map(\.stage))).sorted() }

    public func contains(_ fighter: BattleFighter) -> Bool { fighters.contains(fighter) }

    public func candidates(stage: Int) -> [BattleFighter] { fighters.filter { $0.stage == stage } }
}

public enum BattleMatch: Equatable, Sendable {
    /// The current partner is an egg: no battle.
    case eggBlocked
    /// Stages are equal: fight with this one.
    case ready(BattleFighter)
    /// Mine is lower (or I have nobody chosen): pick one of these, all at the opponent's stage.
    case pick(stage: Int, candidates: [BattleFighter])
    case noSameStage
    /// Mine is higher: the opponent has to make a new QR with a same-stage fighter.
    case opponentMustLower

    public static func match(mine: BattleFighter?, opponent: BattleCard, roster: BattleRoster) -> BattleMatch {
        if roster.isBlockedByEgg { return .eggBlocked }
        // A fighter that is not in this roster counts as no choice.
        if let mine, roster.contains(mine) {
            if mine.stage == opponent.stage { return .ready(mine) }
            if mine.stage > opponent.stage { return .opponentMustLower }
        }
        let candidates = roster.candidates(stage: opponent.stage)
        return candidates.isEmpty ? .noSameStage : .pick(stage: opponent.stage, candidates: candidates)
    }
}
