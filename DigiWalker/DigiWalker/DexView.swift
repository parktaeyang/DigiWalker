import DigiWalkerCore
import SwiftUI

/// Everything the dex screen needs, derived from a snapshot. A v1 snapshot (no dex) only knows the current species.
struct DexModel {
    struct Row: Identifiable {
        let speciesId: String
        let stage: Int?
        let entry: DexEntry?
        let discovered: Bool
        let alsoIn: String?
        /// Used when the species is not in the catalog (e.g. the old starter in a v1 cache).
        var fallbackName: String? = nil
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

    static let cardTitles = ["agu_ex": "아구몬 카드", "gabu_ex": "파피몬 카드", "guil_ex": "길몬 카드"]

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
                              alsoIn: nil, fallbackName: monster.name)
            sections = [Section(title: "현재 파트너", rows: [current])]
            return
        }

        func row(_ id: String, stage: Int?, alsoIn: String? = nil) -> Row {
            Row(speciesId: id, stage: stage, entry: entries[id], discovered: known.contains(id), alsoIn: alsoIn)
        }
        var sections = [Section(title: "공통", rows: [row(SpeciesCatalog.eggId, stage: nil)])]
        var placed = Set<String>()
        for card in SpeciesCatalog.cards {
            var rows: [Row] = []
            for (stage, slots) in card.stages.enumerated() {
                for slot in slots where placed.insert(slot.speciesId).inserted {
                    // Shared species get one row, in the first card (the sprite reference card).
                    let others = SpeciesCatalog.cards.filter { $0.id != card.id && $0.stage(of: slot.speciesId) != nil }
                    let note = others.isEmpty ? nil : others.compactMap { Self.cardTitles[$0.id] }.joined(separator: ", ") + "에도 등장"
                    rows.append(row(slot.speciesId, stage: stage, alsoIn: note))
                }
            }
            sections.append(Section(title: Self.cardTitles[card.id] ?? card.displayName, rows: rows))
        }
        // Poyomon and any species outside the catalog (unknown legacy species) go under "이전 파트너".
        let catalogIds = Set(SpeciesCatalog.all.map(\.id))
        var former: [Row] = legacy ? [row(SpeciesCatalog.legacyPoyomonId, stage: 0)] : []
        for entry in snapshot.dex ?? [] where !catalogIds.contains(entry.speciesId) {
            let name = entry.speciesId == snapshot.monster.speciesId ? snapshot.monster.name : entry.speciesId
            former.append(Row(speciesId: entry.speciesId, stage: nil, entry: entry, discovered: true,
                              alsoIn: nil, fallbackName: name))
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
                if row.speciesId == "omegamon", !row.discovered {
                    Text("특별한 조건이 필요해요").font(.caption2).foregroundStyle(.secondary)
                }
                if let note = row.alsoIn { Text(note).font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
