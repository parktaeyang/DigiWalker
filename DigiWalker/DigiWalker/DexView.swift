import DigiWalkerCore
import SwiftUI

/// Everything the dex screen needs, derived from a snapshot. A v1 snapshot (no dex) only knows the current species.
struct DexModel {
    struct Row: Identifiable {
        let speciesId: String
        let stage: Int?
        let entry: DexEntry?
        let discovered: Bool
        /// True when no card lets random evolution pick this species (Jogress-only: Omegamon, Susanoomon).
        var jogressOnly: Bool = false
        /// Used when the species is not in the catalog (e.g. the old starter in a v1 cache).
        var fallbackName: String? = nil
        /// Item needed before random evolution may pick this species (the original unlock-required species).
        var requiredItem: ItemInfo? = nil
        /// Whether that item is owned; nil when the snapshot predates items.
        var requiredItemOwned: Bool? = nil
        var id: String { speciesId }
        /// Undiscovered rows never expose the real name.
        var displayName: String {
            discovered ? (SpeciesCatalog.info(id: speciesId)?.name ?? fallbackName ?? speciesId) : "???"
        }
    }

    struct Section: Identifiable {
        let title: String
        let rows: [Row]
        var id: String { title }
    }

    static let cardTitles = [
        "agu_ex": "아구몬 카드", "gabu_ex": "파피몬 카드", "guil_ex": "길몬 카드",
        "terrier_ex": "테리어몬 카드", "rena_ex": "레나몬 카드", "agni_ex": "아그니몬 카드",
        "fairi_ex": "페어리몬 카드", "chack_ex": "차크몬 카드", "wolf_ex": "울프몬 카드",
        "blitz_ex": "블리츠몬 카드", "louwe_ex": "로에몬 카드",
    ]

    /// Species that no card lists as a random evolution candidate (needs a special condition to appear).
    static func isJogressOnly(_ speciesId: String) -> Bool {
        SpeciesCatalog.jogressOnlySpeciesIds.contains(speciesId)
    }

    let synced: Bool
    let discoveredCount: Int
    let totalCount: Int
    let sections: [Section]

    init(snapshot: MonsterSnapshot) {
        synced = snapshot.dex != nil
        let entries = Dictionary((snapshot.dex ?? []).map { ($0.speciesId, $0) }, uniquingKeysWith: { first, _ in first })
        let known = synced ? Set(entries.keys) : [snapshot.monster.speciesId]
        let legacy = known.contains(SpeciesCatalog.legacyPoyomonId)
        let universe = SpeciesCatalog.dexUniverse(includingLegacy: legacy)
        totalCount = universe.count
        discoveredCount = universe.filter(known.contains).count
        guard synced else {
            // v1 cache: no dex to trust, so show only the current partner, whatever species it is.
            let monster = snapshot.monster
            let baby = ["botamon", "punimon", "poyomon"].contains(monster.speciesId)
            let current = Row(speciesId: monster.speciesId, stage: monster.stage ?? (baby ? 0 : nil), entry: nil, discovered: true,
                              fallbackName: monster.name)
            sections = [Section(title: "현재 파트너", rows: [current])]
            return
        }

        func row(_ id: String, stage: Int?, requiredItemId: String? = nil) -> Row {
            let item = requiredItemId.flatMap(ItemCatalog.info(id:))
            return Row(speciesId: id, stage: stage, entry: entries[id], discovered: known.contains(id),
                       jogressOnly: Self.isJogressOnly(id), requiredItem: item,
                       requiredItemOwned: item.flatMap { ItemModel.owns($0.id, in: snapshot) })
        }
        var sections = [Section(title: "공통", rows: [row(SpeciesCatalog.eggId, stage: nil)])]
        // Shared species are listed in every card that has them; counts above are per species, so they count once.
        for card in SpeciesCatalog.cards {
            let rows = card.stages.enumerated().flatMap { stage, slots in slots.map { row($0.speciesId, stage: stage, requiredItemId: $0.requiredItemId) } }
            sections.append(Section(title: Self.cardTitles[card.id] ?? card.displayName, rows: rows))
        }
        // Poyomon and any species outside the catalog (unknown legacy species) go under "이전 파트너".
        let catalogIds = Set(SpeciesCatalog.all.map(\.id))
        var former: [Row] = legacy ? [row(SpeciesCatalog.legacyPoyomonId, stage: 0)] : []
        for entry in snapshot.dex ?? [] where !catalogIds.contains(entry.speciesId) {
            let name = entry.speciesId == snapshot.monster.speciesId ? snapshot.monster.name : entry.speciesId
            former.append(Row(speciesId: entry.speciesId, stage: nil, entry: entry, discovered: true,
                              fallbackName: name))
        }
        if !former.isEmpty { sections.append(Section(title: "이전 파트너", rows: former)) }
        self.sections = sections
    }
}

struct DexView: View {
    let snapshot: MonsterSnapshot

    var body: some View {
        let model = DexModel(snapshot: snapshot)
        List {
            if !model.synced {
                Text("워치 앱을 업데이트하면 도감이 동기화돼요. 지금은 현재 파트너만 표시돼요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(model.sections) { section in
                Section(section.title) {
                    ForEach(section.rows) { DexRowView(row: $0, timeZone: snapshot.timeZone ?? .current) }
                }
            }
        }
        .navigationTitle("도감 · \(model.discoveredCount) / \(model.totalCount)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DexRowView: View {
    let row: DexModel.Row
    let timeZone: TimeZone

    private var stageText: String {
        if let stage = row.stage { return StageLabel.text(stage) }
        return row.speciesId == SpeciesCatalog.eggId ? "알" : "이전 파트너"
    }

    private var ownedText: String {
        switch row.requiredItemOwned {
        case true?: " · 보유"
        case false?: " · 미보유"
        case nil: ""
        }
    }

    private func metText(_ entry: DexEntry) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy.MM.dd HH:mm"
        // firstMetSteps is the stage threshold, not the total at the time of the check.
        let what: String
        if row.speciesId == SpeciesCatalog.eggId { what = "모험 시작" }
        else if row.stage == 0 || row.speciesId == SpeciesCatalog.legacyPoyomonId { what = "\(entry.firstMetSteps.formatted())걸음에 부화" }
        else if row.stage != nil { what = "\(entry.firstMetSteps.formatted())걸음에 진화" }
        else { what = "\(entry.firstMetSteps.formatted())걸음 시점" }
        return "처음 확인 \(formatter.string(from: entry.firstMetAt)) · \(what)"
    }

    var body: some View {
        HStack(spacing: 12) {
            PartnerPortrait(speciesId: row.speciesId, slot: 64, concealed: !row.discovered)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName)
                    .font(.headline)
                Text(stageText).font(.caption).foregroundStyle(.secondary)
                if row.discovered, let entry = row.entry {
                    Text(metText(entry)).font(.caption2).foregroundStyle(.secondary)
                }
                if row.jogressOnly, !row.discovered {
                    Text("특별한 조건이 필요해요").font(.caption2).foregroundStyle(.secondary)
                }
                if let item = row.requiredItem {
                    Text("필요: \(item.name)\(ownedText)").font(.caption2)
                        .foregroundStyle(row.requiredItemOwned == true ? Color.green : Color.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
