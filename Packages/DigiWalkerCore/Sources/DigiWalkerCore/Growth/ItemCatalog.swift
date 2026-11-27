import Foundation

/// An evolution item (crest, digimental, ...). Owning one unlocks evolutions; a locked species picked by random evolution consumes one.
public struct ItemInfo: Equatable, Sendable {
    public enum Category: String, Equatable, Sendable, Codable { case crest, digimental, other }

    public let id: String
    /// Korean display name. Every name here is a working draft (see `nameVerified`).
    public let name: String
    public let japaneseName: String
    public let englishName: String
    /// True only when the official Korean name was confirmed. No item has been confirmed yet.
    public let nameVerified: Bool
    public let category: Category
    /// Original work the item comes from.
    public let source: String
}

public enum ItemCatalog {
    private static func entry(_ id: String, _ name: String, _ ja: String, _ en: String,
                              _ category: ItemInfo.Category, _ source: String) -> ItemInfo {
        ItemInfo(id: id, name: name, japaneseName: ja, englishName: en, nameVerified: false,
                 category: category, source: source)
    }

    // The single place for draft Korean names (and their Japanese/English counterparts). Research: Wikimon.
    // Replace a Korean name here once the official one is confirmed, and set nameVerified there.
    public static let all: [ItemInfo] = [
        entry("crest_courage", "용기의 문장", "勇気の紋章", "Crest of Courage", .crest, "디지몬 어드벤처"),
        entry("crest_friendship", "우정의 문장", "友情の紋章", "Crest of Friendship", .crest, "디지몬 어드벤처"),
        entry("crest_love", "사랑의 문장", "愛情の紋章", "Crest of Love", .crest, "디지몬 어드벤처"),
        entry("crest_knowledge", "지식의 문장", "知識の紋章", "Crest of Knowledge", .crest, "디지몬 어드벤처"),
        entry("crest_purity", "순수의 문장", "純真の紋章", "Crest of Purity", .crest, "디지몬 어드벤처"),
        entry("crest_sincerity", "성실의 문장", "誠実の紋章", "Crest of Sincerity", .crest, "디지몬 어드벤처"),
        entry("crest_hope", "희망의 문장", "希望の紋章", "Crest of Hope", .crest, "디지몬 어드벤처"),
        entry("crest_light", "빛의 문장", "光の紋章", "Crest of Light", .crest, "디지몬 어드벤처"),
        entry("crest_kindness", "친절의 문장", "優しさの紋章", "Crest of Kindness", .crest, "디지몬 어드벤처 02"),
        entry("crest_miracles", "기적의 문장", "奇跡の紋章", "Crest of Miracles", .crest, "디지몬 어드벤처 02"),
        entry("crest_fate", "운명의 문장", "運命の紋章", "Crest of Fate", .crest, "디지몬 어드벤처 02"),
        entry("digimental_courage", "용기의 디지멘탈", "勇気のデジメンタル", "Digimental of Courage", .digimental, "디지몬 어드벤처 02"),
        entry("digimental_friendship", "우정의 디지멘탈", "友情のデジメンタル", "Digimental of Friendship", .digimental, "디지몬 어드벤처 02"),
        entry("digimental_love", "사랑의 디지멘탈", "愛情のデジメンタル", "Digimental of Love", .digimental, "디지몬 어드벤처 02"),
        entry("digimental_knowledge", "지식의 디지멘탈", "知識のデジメンタル", "Digimental of Knowledge", .digimental, "디지몬 어드벤처 02"),
        entry("digimental_purity", "순수의 디지멘탈", "純真のデジメンタル", "Digimental of Purity", .digimental, "디지몬 어드벤처 02"),
        entry("digimental_sincerity", "성실의 디지멘탈", "誠実のデジメンタル", "Digimental of Sincerity", .digimental, "디지몬 어드벤처 02"),
        entry("digimental_hope", "희망의 디지멘탈", "希望のデジメンタル", "Digimental of Hope", .digimental, "디지몬 어드벤처 02"),
        entry("digimental_light", "빛의 디지멘탈", "光のデジメンタル", "Digimental of Light", .digimental, "디지몬 어드벤처 02"),
        entry("digimental_kindness", "친절의 디지멘탈", "優しさのデジメンタル", "Digimental of Kindness", .digimental, "디지몬 어드벤처 02"),
        entry("digimental_miracles", "기적의 디지멘탈", "奇跡のデジメンタル", "Digimental of Miracles", .digimental, "디지몬 어드벤처 02"),
        entry("digimental_fate", "운명의 디지멘탈", "運命のデジメンタル", "Digimental of Fate", .digimental, "디지몬 어드벤처 02"),
        entry("x_antibody", "X항체", "X抗体", "X-Antibody", .other, "디지몬 펜듈럼 X"),
        entry("digicore", "디지코어", "デジコア", "Digicore", .other, "디지몬 설정 용어"),
        entry("digicode", "디지코드", "デジコード", "Digicode", .other, "디지몬 프론티어"),
    ]

    public static let ids: [String] = all.map(\.id)

    private static let byId: [String: ItemInfo] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func info(id: String) -> ItemInfo? { byId[id] }
}
