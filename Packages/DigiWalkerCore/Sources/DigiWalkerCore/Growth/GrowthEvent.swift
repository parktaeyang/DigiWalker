import Foundation

/// Picks the Korean postposition that matches the last syllable of a name.
public enum KoreanParticle {
    private static func lastSyllable(_ name: String) -> (isHangul: Bool, finalJamo: Int) {
        guard let scalar = name.unicodeScalars.last(where: { !$0.properties.isWhitespace }) else { return (false, 0) }
        // Hangul syllables U+AC00...U+D7A3: the final consonant index is (value - 0xAC00) % 28 (0 = none).
        guard (0xAC00...0xD7A3).contains(scalar.value) else { return (false, 0) }
        return (true, Int((scalar.value - 0xAC00) % 28))
    }

    /// 이/가
    public static func subject(_ name: String) -> String {
        let s = lastSyllable(name)
        return s.isHangul ? (s.finalJamo == 0 ? "가" : "이") : "이(가)"
    }

    /// 을/를
    public static func object(_ name: String) -> String {
        let s = lastSyllable(name)
        return s.isHangul ? (s.finalJamo == 0 ? "를" : "을") : "을(를)"
    }

    /// 로/으로 (no final consonant or ㄹ final -> 로)
    public static func direction(_ name: String) -> String {
        let s = lastSyllable(name)
        return s.isHangul ? (s.finalJamo == 0 || s.finalJamo == 8 ? "로" : "으로") : "(으)로"
    }
}

/// A hatch or evolution that happened between two states of the same partner.
public struct GrowthEvent: Equatable, Sendable, Codable {
    public enum Kind: String, Equatable, Sendable, Codable { case hatched, evolved }

    public let kind: Kind
    public let monsterId: UUID
    public let fromSpeciesId: String
    public let toSpeciesId: String
    /// Species met between `from` and `to` (exclusive), in order. Best effort: species already in the dex are not listed.
    public let intermediateSpeciesIds: [String]
    /// Evolution steps taken after hatching (hatch itself is not counted).
    public let evolutionSteps: Int

    /// Stable identity of the transition: one per partner generation and species change.
    public var id: String { "\(monsterId.uuidString)-\(fromSpeciesId)-\(toSpeciesId)" }

    /// Nil when the partner generation differs or the species did not change.
    public static func between(_ before: GameState, _ after: GameState) -> GrowthEvent? {
        guard before.monster.id == after.monster.id,
              before.monster.speciesId != after.monster.speciesId else { return nil }
        let known = Set(before.dex.map(\.speciesId))
        let target = after.monster.speciesId
        let intermediates = after.dex.map(\.speciesId).filter { !known.contains($0) && $0 != target }
        let kind: Kind = before.monster.isEgg ? .hatched : .evolved
        let steps: Int
        switch kind {
        case .hatched:
            steps = after.monster.stage ?? intermediates.count
        case .evolved:
            if let from = before.monster.stage, let to = after.monster.stage, to > from {
                steps = to - from
            } else {
                steps = intermediates.count + 1
            }
        }
        return GrowthEvent(kind: kind, monsterId: after.monster.id, fromSpeciesId: before.monster.speciesId,
                           toSpeciesId: target, intermediateSpeciesIds: intermediates, evolutionSteps: steps,
                           fromName: before.monster.name, toName: after.monster.name)
    }

    private let fromName: String
    private let toName: String

    private init(kind: Kind, monsterId: UUID, fromSpeciesId: String, toSpeciesId: String,
                 intermediateSpeciesIds: [String], evolutionSteps: Int, fromName: String, toName: String) {
        self.kind = kind
        self.monsterId = monsterId
        self.fromSpeciesId = fromSpeciesId
        self.toSpeciesId = toSpeciesId
        self.intermediateSpeciesIds = intermediateSpeciesIds
        self.evolutionSteps = evolutionSteps
        self.fromName = fromName
        self.toName = toName
    }

    private func name(of id: String) -> String { SpeciesCatalog.info(id: id)?.name ?? id }

    public var title: String {
        switch kind {
        case .hatched:
            return "\(fromName)\(KoreanParticle.subject(fromName)) 부화했어요!"
        case .evolved:
            if intermediateSpeciesIds.count == 1, let middle = intermediateSpeciesIds.first.map(name(of:)) {
                return "\(fromName)\(KoreanParticle.subject(fromName)) \(middle)\(KoreanParticle.object(middle)) 거쳐 \(toName)\(KoreanParticle.direction(toName)) 진화했어요!"
            }
            if evolutionSteps >= 2 {
                return "\(fromName)\(KoreanParticle.subject(fromName)) \(evolutionSteps)단계 진화해 \(toName)\(KoreanParticle.subject(toName)) 됐어요!"
            }
            return "\(fromName)\(KoreanParticle.subject(fromName)) \(toName)\(KoreanParticle.direction(toName)) 진화했어요!"
        }
    }

    public var body: String {
        switch kind {
        case .hatched:
            if intermediateSpeciesIds.count == 1, let middle = intermediateSpeciesIds.first.map(name(of:)) {
                return "\(middle)\(KoreanParticle.object(middle)) 거쳐 \(toName)\(KoreanParticle.subject(toName)) 됐어요!"
            }
            if evolutionSteps >= 1 {
                return "\(evolutionSteps)단계 진화해 \(toName)\(KoreanParticle.subject(toName)) 됐어요!"
            }
            return "새 파트너 · \(toName)"
        case .evolved:
            return "새 모습 · \(toName)"
        }
    }
}
