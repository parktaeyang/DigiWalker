import DigiWalkerCore
import SwiftUI

struct WatchHomeView: View {
    @ObservedObject var game: WatchGameStore
    private struct Event: Identifiable { let id = UUID(); let title: String; let message: String }
    @State private var event: Event?
    #if DEBUG
    @State private var previewIndex = 0
    #endif
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ScrollView {
            VStack(spacing: 5) {
                if let state = game.state {
                    portrait(state.monster)
                    Text(state.monster.name).font(.headline)
                    PartnerGrowthView(monster: state.monster)
                    let currentDay = state.observedAt.map { state.calendar.isDateInToday($0) } == true
                    Text("오늘 \((currentDay ? state.todaySteps : nil)?.formatted() ?? "—")걸음")
                        .font(.caption)
                }
                Button(game.state?.enrolledAt == nil ? "건강 데이터 연결" : "활동량 갱신") {
                    Task { await game.refresh(requestAccess: true) }
                }
                .disabled(game.busy)
                if let message = game.message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .onChange(of: game.state?.monster.speciesId) { previous, current in
            // nil -> value is the initial load: no alert. A multi-stage jump arrives as one change (final species).
            guard let previous, let current, previous != current else { return }
            let name = game.state?.monster.name ?? current
            if previous == Monster.eggSpeciesId {
                event = Event(title: "디지타마가 부화했어요!", message: "새 모습 · \(name)")
            } else {
                let old = SpeciesCatalog.info(id: previous)?.name ?? previous
                event = Event(title: "\(old)이(가) 진화했어요!", message: "새 모습 · \(name)")
            }
        }
        .alert(event?.title ?? "", isPresented: Binding(get: { event != nil }, set: { if !$0 { event = nil } })) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(event?.message ?? "")
        }
        .task(id: phase) {
            if phase == .active { await game.refresh() }
        }
    }

    @ViewBuilder
    private func portrait(_ monster: Monster) -> some View {
        // starter_acorn still goes through MonsterAssets (private pack) first.
        if monster.speciesId != "starter_acorn", DIMSpriteStore.shared.idleFrames(for: monster.speciesId) != nil
            || PartnerPortrait.bundledSpeciesIds.contains(monster.speciesId) {
            PartnerPortrait(speciesId: monster.speciesId, slot: 64, animated: true)
        } else if case .success(let assets) = MonsterAssets.shared.result,
           let partner = assets.library.species(id: monster.speciesId) {
            #if DEBUG
            let library = assets.library.species
            let partnerIndex = library.firstIndex { $0.speciesId == partner.speciesId } ?? 0
            let species = library[(partnerIndex + previewIndex) % library.count]
            VStack(spacing: 2) {
                sprite(species, source: assets.source)
                if species.speciesId != partner.speciesId {
                    Text("미리보기 · \(species.displayName)").font(.caption2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { previewIndex = (previewIndex + 1) % library.count }
            #else
            sprite(partner, source: assets.source)
            #endif
        } else {
            PartnerPortrait(speciesId: monster.speciesId, slot: 64, animated: true)
        }
    }

    @ViewBuilder
    private func sprite(_ species: DecodedSpecies, source: MonsterAssets.Source) -> some View {
        if source == .starterPack && species.speciesId == "starter_acorn" {
            PartnerPortrait(speciesId: species.speciesId, slot: 64, animated: true)
        } else {
            SpriteView(species: species, pixelSize: 2)
        }
    }
}
