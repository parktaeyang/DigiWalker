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

    /// Stages 0-1 use 32x24x5, stages 2-5 use 64x56x12 in all EX cards.
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
        // Terriermon EX
        ("zerimon", "제리몬", "Zerimon", false),
        ("gummymon", "구미몬", "Gummymon", false),
        ("terriermon", "테리어몬", "Terriermon", false),
        ("galgomon", "갈고몬", "Galgomon", false),
        ("turuiemon", "트루이에몬", "Turuiemon", false),
        ("harpymon", "하피몬", "Harpymon", false),
        ("wendimon", "웬디몬", "Wendimon", false),
        ("rapidmon", "래피드몬", "Rapidmon", false),
        ("sinduramon", "신두라몬", "Sinduramon", false),
        ("makuramon", "마쿠라몬", "Makuramon", false),
        ("andiramon_deva", "안디라몬(데바)", "Andiramon (Deva)", false),
        ("pajiramon", "파지라몬", "Pajiramon", false),
        ("andiramon", "안디라몬", "Andiramon", false),
        ("saintgalgomon", "세인트갈고몬", "Saint Galgomon", false),
        ("cherubimon_virtue", "케루비몬(선)", "Cherubimon (Virtue)", false),
        ("cherubimon_vice", "케루비몬(악)", "Cherubimon (Vice)", false),
        ("rapidmon_armor", "래피드몬(아머)", "Rapidmon (Armor)", false),
        // Renamon EX
        ("relemon", "렐레몬", "Relemon", false),
        ("pokomon", "포코몬", "Pokomon", false),
        ("renamon", "레나몬", "Renamon", false),
        ("kyubimon", "큐우비몬", "Kyubimon", false),
        ("youkomon", "요우코몬", "Youkomon", false),
        ("icedevimon", "아이스데블몬", "Ice Devimon", false),
        ("lynxmon", "링크스몬", "Lynxmon", false),
        ("kumbhiramon", "쿰비라몬", "Kumbhiramon", false),
        ("vikaralamon", "비카라라몬", "Vikaralamon", false),
        ("taomon", "타오몬", "Taomon", false),
        ("doumon", "도우몬", "Doumon", false),
        ("caturamon", "차투라몬", "Caturamon", false),
        ("indaramon", "인다라몬", "Indaramon", false),
        ("sakuyamon", "사쿠야몬", "Sakuyamon", false),
        ("parasimon", "파라시몬", "Parasimon", false),
        ("kuzuhamon_miko", "쿠즈하몬 무녀모드", "Kuzuhamon: Miko Mode", false),
        ("sakuyamon_x", "사쿠야몬 X", "Sakuyamon X", false),
        // Agnimon EX
        ("mokumon", "모쿠몬", "Mokumon", false),
        ("petimeramon", "쁘띠메라몬", "Peti Meramon", false),
        ("flamon", "플라몬", "Flamon", false),
        ("gottsumon", "곳츠몬", "Gottsumon", false),
        ("agnimon", "아그니몬", "Agnimon", false),
        ("meramon", "메라몬", "Meramon", false),
        ("starmon", "스타몬", "Starmon", false),
        ("grottemon", "그로토몬", "Grottemon", false),
        ("aldamon", "알다몬", "Aldamon", false),
        ("vritramon", "브리트라몬", "Vritramon", false),
        ("superstarmon", "슈퍼스타몬", "Super Starmon", false),
        ("gigasmon", "기가스몬", "Gigasmon", false),
        ("darksuperstarmon", "다크슈퍼스타몬", "Dark Super Starmon", false),
        ("kaisergreymon", "카이저그레이몬", "Kaiser Greymon", false),
        ("ancientgreymon", "에인션트그레이몬", "Ancient Greymon", false),
        ("ancientvolcamon", "에인션트볼케이몬", "Ancient Volcamon", false),
        ("susanoomon", "스사노오몬", "Susanoomon", false),
        // Fairimon EX
        ("yuramon", "유라몬", "Yuramon", false),
        ("tanemon", "타네몬", "Tanemon", false),
        ("tinkermon", "팅커몬", "Tinkermon", false),
        ("pomumon", "포무몬", "Pomumon", false),
        ("fairimon", "페어리몬", "Fairimon", false),
        ("cockatrimon", "코카트리몬", "Cockatrimon", false),
        ("arbormon", "아르보르몬", "Arbormon", false),
        ("zassoumon", "잣소우몬", "Zassoumon", false),
        ("jetsilphymon", "제트실피몬", "Jet Silphymon", false),
        ("shutumon", "슈츠몬", "Shutumon", false),
        ("petaldramon", "페탈드라몬", "Petaldramon", false),
        ("peacockmon", "피콕몬", "Peacockmon", false),
        ("zamielmon", "자미엘몬", "Zamielmon", false),
        ("ancientirismon", "에인션트이리스몬", "Ancient Irismon", false),
        ("lotusmon", "로터스몬", "Lotusmon", false),
        ("ancienttroiamon", "에인션트트로이아몬", "Ancient Troiamon", false),
        ("lordknightmon", "로드나이트몬", "Lord Knightmon", false),
        // Chackmon EX
        ("yukimibotamon", "유키미보타몬", "Yukimibotamon", false),
        ("hiyarimon", "히야리몬", "Hiyarimon", false),
        ("bearmon", "베어몬", "Bearmon", false),
        ("snowgoblimon", "스노우고블리몬", "Snow Goblimon", false),
        ("chackmon", "차크몬", "Chackmon", false),
        ("gryzmon", "그리즈몬", "Gryzmon", false),
        ("icemon", "아이스몬", "Icemon", false),
        ("mojyamon", "모쟈몬", "Mojyamon", false),
        ("daipenmon", "다이펜몬", "Daipenmon", false),
        ("blizzarmon", "블리자몬", "Blizzarmon", false),
        ("panjyamon_x", "판쟈몬 X", "Panjyamon X", false),
        ("nanomon", "나노몬", "Nanomon", false),
        ("astamon", "아스타몬", "Astamon", false),
        ("olegmon", "올레그몬", "Olegmon", false),
        ("frosvelgrmon", "프로스벨그몬", "Fros Velgrmon", false),
        ("ancientmegatheriumon", "에인션트메가테리움몬", "Ancient Megatheriumon", false),
        ("dynasmon", "다이나스몬", "Dynasmon", false),
        // Wolfmon EX
        ("wanyamon", "와냐몬", "Wanyamon", false),
        ("strabimon", "스트라비몬", "Strabimon", false),
        ("gizamon", "기자몬", "Gizamon", false),
        ("wolfmon", "울프몬", "Wolfmon", false),
        ("dobermon", "도베르몬", "Dobermon", false),
        ("ranamon", "라나몬", "Ranamon", false),
        ("ebidramon", "에비드라몬", "Ebidramon", false),
        ("beowolfmon", "베오울프몬", "Beowolfmon", false),
        ("garummon", "가룸몬", "Garummon", false),
        ("calamaramon", "칼라마라몬", "Calamaramon", false),
        ("sirenmon", "사이렌몬", "Sirenmon", false),
        ("splashmon", "스플래시몬", "Splashmon", false),
        ("magnagarurumon", "매그나가루몬", "Magna Garurumon", false),
        ("ancientgarurumon", "에인션트가루몬", "Ancient Garurumon", false),
        ("ancientmermaimon", "에인션트머메이몬", "Ancient Mermaimon", false),
        // Blitzmon EX
        ("choromon", "쵸로몬", "Choromon", false),
        ("caprimon", "카프리몬", "Caprimon", false),
        ("kokabuterimon", "코카부테리몬", "Kokabuterimon", false),
        ("kokuwamon", "코쿠와몬", "Kokuwamon", false),
        ("blitzmon", "블리츠몬", "Blitzmon", false),
        ("thunderballmon", "썬더볼몬", "Thunderballmon", false),
        ("mercuremon", "메르큐리몬", "Mercuremon", false),
        ("bladekuwagamon", "블레이드쿠와가몬", "Blade Kuwagamon", false),
        ("rhinokabuterimon", "라이노카부테리몬", "Rhino Kabuterimon", false),
        ("bolgmon", "볼그몬", "Bolgmon", false),
        ("sephirothmon", "세피로트몬", "Sephirothmon", false),
        ("metallifekuwagamon", "메탈라이프쿠와가몬", "Metallife Kuwagamon", false),
        ("wisemon", "와이즈몬", "Wisemon", false),
        ("ancientbeatmon", "에인션트비트몬", "Ancient Beatmon", false),
        ("grandiskuwagamon", "그란디스쿠와가몬", "Grandis Kuwagamon", false),
        ("ancientwisemon", "에인션트와이즈몬", "Ancient Wisemon", false),
        ("murmukusmon", "무르무쿠스몬", "Murmukusmon", false),
        // Louwemon EX
        ("popomon", "포포몬", "Popomon", false),
        ("frimon", "프리몬", "Frimon", false),
        ("liollmon", "리올몬", "Liollmon", false),
        ("gazimon", "가지몬", "Gazimon", false),
        ("louwemon", "로에몬", "Louwemon", false),
        ("liamon", "리아몬", "Liamon", false),
        ("duskmon", "더스크몬", "Duskmon", false),
        ("madleomon", "매드레오몬", "Mad Leomon", false),
        ("raihimon", "라이히몬", "Raihimon", false),
        ("kaiserleomon", "카이저레오몬", "Kaiser Leomon", false),
        ("loaderleomon", "로더레오몬", "Loader Leomon", false),
        ("velgrmon", "벨그몬", "Velgrmon", false),
        ("skullsatamon", "스컬사타몬", "Skull Satamon", false),
        ("lucemon_falldown", "루체몬 폴다운모드", "Lucemon: Falldown Mode", false),
        ("deathmon", "데스몬", "Deathmon", false),
        ("dinotigermon", "다이노타이거몬", "Dinotigermon", false),
        ("ancientsphinxmon", "에인션트스핑크스몬", "Ancient Sphinxmon", false),
    ]

    /// `agu_ex` must stay first: legacy Botamon migration and shared-species base cards depend on card order.
    public static let cards: [EvolutionCard] = [
        .agumonEX, .gabumonEX, .guilmonEX, .terriermonEX, .renamonEX, .agnimonEX,
        .fairimonEX, .chackmonEX, .wolfmonEX, .blitzmonEX, .louwemonEX,
    ]

    /// Egg, legacy Poyomon, then every card species once (first card order, then stage order).
    public static let all: [SpeciesInfo] = names.map { id, name, english, verified in
        let stage = cards.lazy.compactMap { $0.stage(of: id) }.first
        return SpeciesInfo(id: id, name: name, englishName: english, nameVerified: verified,
                           dimSprite: stage.map(DIMSpriteSpec.forStage))
    }

    private static let byId: [String: SpeciesInfo] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func info(id: String) -> SpeciesInfo? { byId[id] }

    public static func card(id: String) -> EvolutionCard? { cards.first { $0.id == id } }

    /// Distinct species of all cards in discovery-list order (shared species appear once).
    public static let cardSpeciesIds: [String] = {
        var seen = Set<String>()
        return cards.flatMap { $0.stages.flatMap { $0.map(\.speciesId) } }.filter { seen.insert($0).inserted }
    }()

    /// Species that no card lists as a random evolution candidate (Jogress-only), computed once.
    public static let jogressOnlySpeciesIds: Set<String> = Set(cardSpeciesIds.filter { id in
        cards.allSatisfy { $0.slot(of: id)?.randomEligible != true }
    })

    /// Species a dex can show: egg + card species (+ legacy Poyomon when it was met).
    public static func dexUniverse(includingLegacy: Bool) -> [String] {
        [eggId] + cardSpeciesIds + (includingLegacy ? [legacyPoyomonId] : [])
    }
}
