import DigiWalkerCore
import SwiftUI

struct WatchHomeView: View {
    @ObservedObject var game: WatchGameStore
    @State private var showsHatch = false
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
            if previous == Monster.eggSpeciesId, let current, Hatchling(rawValue: current) != nil {
                showsHatch = true
            }
        }
        .alert("디지타마가 부화했어요!", isPresented: $showsHatch) {
            Button("확인", role: .cancel) { }
        } message: {
            if let name = game.state?.monster.name { Text("새 파트너 · \(name)") }
        }
        .task(id: phase) {
            if phase == .active { await game.refresh() }
        }
    }

    @ViewBuilder
    private func portrait(_ monster: Monster) -> some View {
        if monster.isEgg || monster.hatchling != nil {
            PartnerPortrait(speciesId: monster.speciesId, animated: true).frame(width: 64, height: 64)
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
        }
    }

    @ViewBuilder
    private func sprite(_ species: DecodedSpecies, source: MonsterAssets.Source) -> some View {
        if source == .starterPack && species.speciesId == "starter_acorn" {
            PartnerPortrait(speciesId: species.speciesId, animated: true).frame(width: 64, height: 64)
        } else {
            SpriteView(species: species, pixelSize: 2)
        }
    }
}
