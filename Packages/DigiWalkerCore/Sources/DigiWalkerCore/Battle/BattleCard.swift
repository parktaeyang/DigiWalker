import Foundation

extension SpeciesCatalog {
    /// Card stage 0...5 of a species for battles. Nil for the egg, legacy Poyomon (no card lists it) and unknown ids.
    /// Shared species sit at the same stage in every card (`SpeciesCatalogTests`), so the first card decides.
    public static func battleStage(of speciesId: String) -> Int? {
        cards.lazy.compactMap { $0.stage(of: speciesId) }.first
    }
}

public enum BattleCardError: Error, Equatable, Sendable {
    case tooLong
    case notBattleCode
    case malformed
    case unsupportedVersion(Int)
    case unknownSpecies
    case egg
    /// Known species without a card stage (legacy Poyomon).
    case notEligible
    case stageMismatch
}

/// What a QR code carries: format version, species id, name and stage. No health data and no partner id.
/// Format (ASCII only): `digiwalker-battle:1?s=<speciesId>&t=<stage>&n=<percent-encoded UTF-8 name>`.
public struct BattleCard: Equatable, Sendable {
    public static let formatVersion = 1
    public static let prefix = "digiwalker-battle:"
    public static let maxPayloadBytes = 512
    public static let maxNameLength = 32

    public let speciesId: String
    public let name: String
    public let stage: Int

    /// Nil for the egg, species without a card stage, an invalid name, or a card whose payload would exceed
    /// `maxPayloadBytes` (so every card that can be built can also be decoded). The stage comes from the catalog.
    /// The name is stored trimmed of surrounding whitespace.
    public init?(speciesId: String, name: String) {
        let trimmed = Self.trimmed(name)
        guard let stage = SpeciesCatalog.battleStage(of: speciesId), Self.isValid(name: trimmed) else { return nil }
        self.speciesId = speciesId
        self.name = trimmed
        self.stage = stage
        guard encoded().utf8.count <= Self.maxPayloadBytes else { return nil }
    }

    private init(validatedSpeciesId: String, name: String, stage: Int) {
        speciesId = validatedSpeciesId
        self.name = name
        self.stage = stage
    }

    public func encoded() -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let escaped = name.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return "\(Self.prefix)\(Self.formatVersion)?s=\(speciesId)&t=\(stage)&n=\(escaped)"
    }

    public static func decode(_ text: String) -> Result<BattleCard, BattleCardError> {
        guard text.utf8.count <= maxPayloadBytes else { return .failure(.tooLong) }
        guard text.hasPrefix(prefix) else { return .failure(.notBattleCode) }
        let rest = text.dropFirst(prefix.count)
        // Only the leading digits are the version, so `2/...` or `2:...` also reads as a version problem.
        let digits = rest.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, let version = Int(digits) else { return .failure(.malformed) }
        // Checked before the keys: a future format may use other keys, which must read as "update the app".
        guard version == formatVersion else { return .failure(.unsupportedVersion(version)) }
        let afterVersion = rest.dropFirst(digits.count)
        guard afterVersion.first == "?" else { return .failure(.malformed) }
        let question = afterVersion.startIndex

        var values: [String: String] = [:]
        for part in afterVersion[afterVersion.index(after: question)...].split(separator: "&", omittingEmptySubsequences: false) {
            guard let eq = part.firstIndex(of: "=") else { return .failure(.malformed) }
            let key = String(part[..<eq])
            guard ["s", "t", "n"].contains(key), values[key] == nil else { return .failure(.malformed) }
            values[key] = String(part[part.index(after: eq)...])
        }
        guard let species = values["s"], let stageText = values["t"], let rawName = values["n"] else {
            return .failure(.malformed)
        }

        guard isValid(speciesId: species), SpeciesCatalog.info(id: species) != nil else {
            return .failure(.unknownSpecies)
        }
        if species == SpeciesCatalog.eggId { return .failure(.egg) }
        guard let catalogStage = SpeciesCatalog.battleStage(of: species) else { return .failure(.notEligible) }
        guard stageText.utf8.count == 1, let stage = Int(stageText), (0...5).contains(stage), stage == catalogStage else {
            return .failure(.stageMismatch)
        }
        // The raw name is what the encoder writes: unreserved characters and `%HH` escapes, nothing else. That keeps
        // any accepted card within the length limit when it is encoded again.
        guard isEncodedName(rawName), let decoded = rawName.removingPercentEncoding else {
            return .failure(.malformed)
        }
        let name = trimmed(decoded)
        guard isValid(name: name) else { return .failure(.malformed) }
        return .success(BattleCard(validatedSpeciesId: species, name: name, stage: stage))
    }

    private static func isEncodedName(_ raw: String) -> Bool {
        let bytes = Array(raw.utf8)
        var i = 0
        func isHex(_ b: UInt8) -> Bool { (48...57).contains(b) || (65...70).contains(b) || (97...102).contains(b) }
        while i < bytes.count {
            let b = bytes[i]
            if b == 37 { // %
                guard i + 2 < bytes.count, isHex(bytes[i + 1]), isHex(bytes[i + 2]) else { return false }
                i += 3
            } else {
                let unreserved = (65...90).contains(b) || (97...122).contains(b) || (48...57).contains(b)
                    || b == 45 || b == 46 || b == 95 || b == 126
                guard unreserved else { return false }
                i += 1
            }
        }
        return true
    }

    private static func isValid(speciesId: String) -> Bool {
        (1...64).contains(speciesId.utf8.count)
            && speciesId.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }
    }

    private static func trimmed(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Expects an already trimmed name: non-empty, at most 32 characters, no control, format or line/paragraph
    /// separator characters.
    private static func isValid(name: String) -> Bool {
        !name.isEmpty && name.count <= maxNameLength
            && !name.unicodeScalars.contains {
                [.control, .format, .lineSeparator, .paragraphSeparator].contains($0.properties.generalCategory)
            }
    }
}
