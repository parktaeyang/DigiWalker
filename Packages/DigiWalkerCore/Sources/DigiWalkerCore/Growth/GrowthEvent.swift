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

    /// 와/과
    public static func with(_ name: String) -> String {
        let s = lastSyllable(name)
        return s.isHangul ? (s.finalJamo == 0 ? "와" : "과") : "와(과)"
    }

    /// 로/으로 (no final consonant or ㄹ final -> 로)
    public static func direction(_ name: String) -> String {
        let s = lastSyllable(name)
        return s.isHangul ? (s.finalJamo == 0 || s.finalJamo == 8 ? "로" : "으로") : "(으)로"
    }
}

/// A hatch, evolution or item find that happened between two states of the same partner.
public struct GrowthEvent: Equatable, Sendable, Codable {
    public enum Kind: String, Equatable, Sendable, Codable { case hatched, evolved, itemFound }

    public let kind: Kind
    public let monsterId: UUID
    public let fromSpeciesId: String
    public let toSpeciesId: String
    /// Species met between `from` and `to` (exclusive), in order. Best effort: species already in the dex are not listed.
    public let intermediateSpeciesIds: [String]
    /// Evolution steps taken after hatching (hatch itself is not counted).
    public let evolutionSteps: Int
    /// Only for `.itemFound`. Optional so queue files written before items existed still decode.
    public let itemId: String?
    public let segment: Int?

    /// Stable identity: one per partner generation and species change, or per item segment.
    public var id: String {
        if kind == .itemFound, let segment { return "\(monsterId.uuidString)-item-\(segment)" }
        return "\(monsterId.uuidString)-\(fromSpeciesId)-\(toSpeciesId)"
    }

    /// Items granted in `after` that `before` did not have, oldest segment first. Empty for another partner.
    public static func items(between before: GameState, _ after: GameState) -> [GrowthEvent] {
        guard before.monster.id == after.monster.id else { return [] }
        let known = Set(before.items.map { "\($0.monsterId.uuidString)#\($0.segment)" })
        return after.items
            .filter { $0.monsterId == after.monster.id && !known.contains("\($0.monsterId.uuidString)#\($0.segment)") }
            .sorted { $0.segment < $1.segment }
            .map { grant in
                GrowthEvent(kind: .itemFound, monsterId: grant.monsterId, fromSpeciesId: after.monster.speciesId,
                            toSpeciesId: after.monster.speciesId, intermediateSpeciesIds: [], evolutionSteps: 0,
                            fromName: after.monster.name, toName: after.monster.name,
                            itemId: grant.itemId, segment: grant.segment)
            }
    }

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
        case .itemFound:
            return nil // item events come from `items(between:_:)`
        case .evolved:
            if let from = before.monster.stage, let to = after.monster.stage, to > from {
                steps = to - from
            } else {
                steps = intermediates.count + 1
            }
        }
        return GrowthEvent(kind: kind, monsterId: after.monster.id, fromSpeciesId: before.monster.speciesId,
                           toSpeciesId: target, intermediateSpeciesIds: intermediates, evolutionSteps: steps,
                           fromName: before.monster.name, toName: after.monster.name,
                           itemId: nil, segment: nil)
    }

    private let fromName: String
    private let toName: String

    private enum CodingKeys: String, CodingKey {
        case kind, monsterId, fromSpeciesId, toSpeciesId, intermediateSpeciesIds, evolutionSteps, itemId, segment
        case fromName, toName
    }

    /// Queue files outlive app versions, so an item event must carry a usable segment: the body multiplies it by
    /// 5,000. Hatch and evolution events written before items existed have none and stay readable.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        monsterId = try c.decode(UUID.self, forKey: .monsterId)
        fromSpeciesId = try c.decode(String.self, forKey: .fromSpeciesId)
        toSpeciesId = try c.decode(String.self, forKey: .toSpeciesId)
        intermediateSpeciesIds = try c.decode([String].self, forKey: .intermediateSpeciesIds)
        evolutionSteps = try c.decode(Int.self, forKey: .evolutionSteps)
        fromName = try c.decode(String.self, forKey: .fromName)
        toName = try c.decode(String.self, forKey: .toName)
        itemId = try c.decodeIfPresent(String.self, forKey: .itemId)
        segment = try c.decodeIfPresent(Int.self, forKey: .segment)
        if kind == .itemFound {
            guard let segment, (1...(Int.max / ItemDrop.stepsPerSegment)).contains(segment) else {
                throw DecodingError.dataCorruptedError(forKey: .segment, in: c,
                    debugDescription: "item event segment is missing or out of range")
            }
        }
    }

    private init(kind: Kind, monsterId: UUID, fromSpeciesId: String, toSpeciesId: String,
                 intermediateSpeciesIds: [String], evolutionSteps: Int, fromName: String, toName: String,
                 itemId: String?, segment: Int?) {
        self.kind = kind
        self.monsterId = monsterId
        self.fromSpeciesId = fromSpeciesId
        self.toSpeciesId = toSpeciesId
        self.intermediateSpeciesIds = intermediateSpeciesIds
        self.evolutionSteps = evolutionSteps
        self.fromName = fromName
        self.toName = toName
        self.itemId = itemId
        self.segment = segment
    }

    private func name(of id: String) -> String { SpeciesCatalog.info(id: id)?.name ?? id }

    private var itemName: String { itemId.map { ItemCatalog.info(id: $0)?.name ?? $0 } ?? "아이템" }

    public var title: String {
        switch kind {
        case .itemFound:
            return "\(itemName)\(KoreanParticle.object(itemName)) 얻었어요!"
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
        case .itemFound:
            // No species name: the partner may have evolved since the drop. Fixed locale so the text never varies.
            let steps = ((segment ?? 1) * ItemDrop.stepsPerSegment).formatted(.number.locale(Locale(identifier: "en_US")))
            return "누적 \(steps)걸음을 넘겨 찾았어요"
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
