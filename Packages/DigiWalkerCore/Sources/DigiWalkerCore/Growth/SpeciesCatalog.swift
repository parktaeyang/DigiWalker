import Foundation

/// Frame layout of a species in a DIM sprite sheet. `idleFrames` are assumed, not verified against real sheets.
public struct DIMSpriteSpec: Equatable, Sendable {
    public let frameWidth: Int
    public let frameHeight: Int
    public let frameCount: Int
    public let idleFrames: [Int]

    public init(frameWidth: Int, frameHeight: Int, frameCount: Int, idleFrames: [Int] = [0, 1]) {
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.frameCount = frameCount
        self.idleFrames = idleFrames
    }

    /// Stages 0-1 use 32x24x5, stages 2-5 use 64x56x12 in all three EX cards.
    static func forStage(_ stage: Int) -> DIMSpriteSpec {
        stage <= 1
            ? DIMSpriteSpec(frameWidth: 32, frameHeight: 24, frameCount: 5)
            : DIMSpriteSpec(frameWidth: 64, frameHeight: 56, frameCount: 12)
    }
}

public struct SpeciesInfo: Equatable, Sendable {
    public let id: String
    /// Korean display name. `nameVerified == false` means the name is a placeholder awaiting confirmation.
    public let name: String
    public let englishName: String
    public let nameVerified: Bool
    public let dimSprite: DIMSpriteSpec?
}

public enum SpeciesCatalog {
    public static let eggId = "digitama"
    public static let legacyPoyomonId = "poyomon"

    // All Korean display names live in this one table so unverified ones are easy to change later.
    // (id, 한국어 표시명, English, nameVerified)
    private static let names: [(String, String, String, Bool)] = [
        ("digitama", "디지타마", "Digitama", true),
        ("poyomon", "포요몬", "Poyomon", true),
        // Agumon EX
        ("botamon", "깜몬", "Botamon", true),
        ("koromon", "코로몬", "Koromon", true),
        ("agumon", "아구몬", "Agumon", true),
        ("greymon", "그레이몬", "Greymon", true),
        ("coelamon", "실라몬", "Coelamon", false),
        ("ogremon", "오거몬", "Ogremon", false),
        ("algomon_adult", "알고몬(성숙기)", "Algomon (Adult)", false),
        ("metalgreymon_vaccine", "메탈그레이몬(백신)", "Metal Greymon (Vaccine)", false),
        ("andromon", "안드로몬", "Andromon", true),
        ("anomalocarimon", "아노말로카리몬", "Anomalocarimon", false),
        ("mamemon", "마메몬", "Mamemon", false),
        ("neodevimon", "네오데블몬", "Neo Devimon", false),
        ("metaltyranomon", "메탈티라노몬", "Metal Tyranomon", false),
        ("wargreymon", "워그레이몬", "War Greymon", true),
        ("omegamon", "오메가몬", "Omegamon", true),
        ("blitzgreymon", "블리츠그레이몬", "Blitz Greymon", false),
        ("donedevimon", "돈데블몬", "Done Devimon", false),
        // Gabumon EX
        ("punimon", "푸니몬", "Punimon", true),
        ("tsunomon", "쯔노몬", "Tsunomon", true),
        ("gabumon", "파피몬", "Gabumon", true),
        ("garurumon", "가루몬", "Garurumon", true),
        ("gorimon", "고리몬", "Gorimon", false),
        ("dokugumon", "도쿠구몬", "Dokugumon", false),
        ("weregarurumon", "워가루몬", "Were Garurumon", true),
        ("parrotmon", "패럿몬", "Parrotmon", false),
        ("valvemon", "밸브몬", "Valvemon", false),
        ("bigmamemon", "빅마메몬", "Big Mamemon", false),
        ("orochimon", "오로치몬", "Orochimon", false),
        ("waruseadramon", "와루시드라몬", "Waru Seadramon", false),
        ("metalgarurumon", "메탈가루몬", "Metal Garurumon", true),
        ("cresgarurumon", "크레스가루몬", "Cres Garurumon", false),
        ("nidhoggmon", "니드호그몬", "Nidhoggmon", false),
        // Guilmon EX
        ("jyarimon", "쟈리몬", "Jyarimon", false),
        ("gigimon", "지지몬", "Gigimon", false),
        ("guilmon", "길몬", "Guilmon", true),
        ("siesamon", "시사몬", "Siesamon", false),
        ("growmon_orange", "그라우몬(오렌지)", "Growmon (Orange)", false),
        ("growmon", "그라우몬", "Growmon", true),
        ("devidramon", "데블드라몬", "Devidramon", false),
        ("vajramon", "바즈라몬", "Vajramon", false),
        ("majiramon", "마지라몬", "Majiramon", false),
        ("mihiramon", "미히라몬", "Mihiramon", false),
        ("megalogrowmon_orange", "메가로그라우몬(오렌지)", "Megalo Growmon (Orange)", false),
        ("megalogrowmon", "메가로그라우몬", "Megalo Growmon", true),
        ("sandiramon", "산디라몬", "Sandiramon", false),
        ("dukemon", "듀크몬", "Dukemon", true),
        ("dukemon_x", "듀크몬 X", "Dukemon X", false),
        ("megidramon", "메기드라몬", "Megidramon", false),
        ("dukemon_crimson", "듀크몬 크림슨모드", "Dukemon: Crimson Mode", false),
    ]

    public static let cards: [EvolutionCard] = [.agumonEX, .gabumonEX, .guilmonEX]

    /// Egg, legacy Poyomon, then every card species once (first card order, then stage order).
    public static let all: [SpeciesInfo] = names.map { id, name, english, verified in
        let stage = cards.lazy.compactMap { $0.stage(of: id) }.first
        return SpeciesInfo(id: id, name: name, englishName: english, nameVerified: verified,
                           dimSprite: stage.map(DIMSpriteSpec.forStage))
    }

    private static let byId: [String: SpeciesInfo] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func info(id: String) -> SpeciesInfo? { byId[id] }

    public static func card(id: String) -> EvolutionCard? { cards.first { $0.id == id } }

    /// Distinct species of the three cards in discovery-list order (shared species appear once).
    public static let cardSpeciesIds: [String] = {
        var seen = Set<String>()
        return cards.flatMap { $0.stages.flatMap { $0.map(\.speciesId) } }.filter { seen.insert($0).inserted }
    }()

    /// Species a dex can show: egg + card species (+ legacy Poyomon when it was met).
    public static func dexUniverse(includingLegacy: Bool) -> [String] {
        [eggId] + cardSpeciesIds + (includingLegacy ? [legacyPoyomonId] : [])
    }
}
