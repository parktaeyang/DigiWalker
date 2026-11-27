import DigiWalkerCore
import SwiftUI

/// Everything the item screen needs, derived from a snapshot. Only the 25 catalog items are listed;
/// an item id this build does not know is ignored. A v1/v2 snapshot has no items at all.
struct ItemModel {
    struct Row: Identifiable {
        let info: ItemInfo
        let count: Int
        let firstGrantedAt: Date?
        /// True when some species needs this item to be an evolution candidate.
        let unlocksEvolution: Bool
        var owned: Bool { count > 0 }
        var id: String { info.id }
    }

    struct Section: Identifiable {
        let title: String
        let rows: [Row]
        var id: String { title }
    }

    let synced: Bool
    let ownedKinds: Int
    let totalKinds: Int
    let sections: [Section]

    private static let unlockItemIds: Set<String> = Set(SpeciesCatalog.cards.flatMap(\.requiredItemIds))

    init(snapshot: MonsterSnapshot) {
        synced = snapshot.items != nil
        let found = Dictionary((snapshot.items ?? []).map { ($0.itemId, $0) }, uniquingKeysWith: { first, _ in first })
        let rows = ItemCatalog.all.map { info in
            Row(info: info, count: found[info.id]?.count ?? 0, firstGrantedAt: found[info.id]?.firstGrantedAt,
                unlocksEvolution: Self.unlockItemIds.contains(info.id))
        }
        totalKinds = rows.count
        ownedKinds = rows.filter(\.owned).count
        let titles: [(ItemInfo.Category, String)] = [(.crest, "문장"), (.digimental, "디지멘탈"), (.other, "기타")]
        sections = titles.map { category, title in Section(title: title, rows: rows.filter { $0.info.category == category }) }
    }

    /// True if the snapshot says the partner owns the item. Nil when the snapshot predates items (unknown).
    static func owns(_ itemId: String, in snapshot: MonsterSnapshot) -> Bool? {
        snapshot.items.map { $0.contains { $0.itemId == itemId && $0.count > 0 } }
    }
}

struct ItemView: View {
    let snapshot: MonsterSnapshot

    var body: some View {
        let model = ItemModel(snapshot: snapshot)
        List {
            if !model.synced {
                Text("워치 앱을 업데이트하면 아이템이 동기화돼요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(model.sections) { section in
                Section(section.title) {
                    ForEach(section.rows) { ItemRowView(row: $0, synced: model.synced) }
                }
            }
            Text("\(ItemDrop.stepsPerSegment.formatted())걸음마다 20% 확률로 아이템을 하나 찾아요. 잠금 진화에 쓰면 1개가 사라져요. 이름은 임시예요.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle(model.synced ? "아이템 · \(model.ownedKinds) / \(model.totalKinds)" : "아이템")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ItemRowView: View {
    let row: ItemModel.Row
    /// False for a v1/v2 cache: "not owned" is unknown there, so the count column shows a waiting mark instead.
    let synced: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.info.name).font(.headline)
                Text(row.info.source).font(.caption).foregroundStyle(.secondary)
                if row.unlocksEvolution {
                    Text("특정 진화에 필요해요").font(.caption2).foregroundStyle(.secondary)
                }
                if let date = row.firstGrantedAt {
                    Text("처음 얻은 날 \(DisplayFormat.dateTime(date))").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(!synced ? "동기화 대기" : row.owned ? "×\(row.count)" : "미보유").font(.callout.monospacedDigit())
                .foregroundStyle(synced && row.owned ? Color.primary : Color.secondary)
        }
        .opacity(synced && !row.owned ? 0.45 : 1)
        .accessibilityElement(children: .combine)
    }
}
