import DigiWalkerCore
import SwiftUI

struct WatchHomeView: View {
    @ObservedObject var game: WatchGameStore
    #if DEBUG
    @State private var previewIndex = 0
    #endif
    @Environment(\.scenePhase) private var phase
    /// The event the alert is showing. Tracked here so the next queued event gets a fresh presentation.
    @State private var presented: GrowthEvent?
    /// True from closing an alert until the pause before the next one ends. Only the pause task presents then.
    @State private var closing = false
    @State private var showingLog = false
    @State private var showingItems = false

    var body: some View {
        ScrollView {
            VStack(spacing: 5) {
                if let state = game.state {
                    portrait(state.monster)
                    Text(state.monster.name).font(.headline)
                    PartnerGrowthView(monster: state.monster)
                    if state.items.isEmpty {
                        Text("\(ItemDrop.stepsPerSegment.formatted())걸음마다 아이템을 찾을 수 있어요")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Button("아이템 \(state.items.count)개") { showingItems = true }
                            .font(.caption)
                            .accessibilityIdentifier("itemsButton")
                    }
                    let currentDay = state.observedAt.map { state.calendar.isDateInToday($0) } == true
                    Text("오늘 \((currentDay ? state.todaySteps : nil)?.formatted() ?? "—")걸음")
                        .font(.caption)
                }
                Button(game.state?.enrolledAt == nil ? "건강 데이터 연결" : "활동량 갱신") {
                    Task { await game.refresh(requestAccess: true) }
                }
                .disabled(game.busy)
                if game.notificationsEnabled == false {
                    Text("알림이 꺼져 있어 앱을 열 때만 알려 드려요").font(.footnote).foregroundStyle(.secondary)
                } else if game.notificationsEnabled == true {
                    Text("앱을 닫아 두어도 부화·진화·아이템을 알려 드려요. 알림은 수십 분에서 1시간 정도 늦을 수 있어요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let message = game.message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                Button {
                    showingLog = true
                } label: {
                    Text(game.wakeData.summary(now: .now))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("backgroundLogSummary")
            }
            .frame(maxWidth: .infinity)
        }
        .alert(presented?.title ?? "", isPresented: Binding(
            get: { presented != nil },
            set: { if !$0 { closeAlert() } }
        )) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(presented?.body ?? "")
        }
        // First presentation only; the next queued event is presented by closeAlert after its pause.
        .onChange(of: game.presentableAlerts, initial: true) { _, _ in
            if presented == nil, !closing { presented = game.pendingAlert }
        }
        .task(id: phase) {
            if phase == .active { await game.refresh() }
        }
        .onAppear { game.loadWakeLog() }
        .sheet(isPresented: $showingLog) { BackgroundLogView(entries: game.wakeData.entries) }
        .sheet(isPresented: $showingItems) {
            if let state = game.state { WatchItemsView(summaries: state.itemSummaries) }
        }
    }

    private func closeAlert() {
        guard let shown = presented else { return }
        closing = true
        presented = nil
        game.dismissAlert(id: shown.id)
        // Present the next queued event after this alert has fully gone away.
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            closing = false
            if presented == nil { presented = game.pendingAlert }
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

/// Recent wake-ups, newest first. For checking how often the system lets the app run in the background.
struct BackgroundLogView: View {
    let entries: [BackgroundLogEntry]

    var body: some View {
        List {
            if entries.isEmpty {
                Text("기록이 없어요").font(.footnote)
            }
            ForEach(entries.reversed()) { entry in
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.at.formatted(.dateTime.month().day().hour().minute().second())).font(.caption2)
                    Text("\(entry.source.label) · \(entry.outcome.label)").font(.caption)
                }
            }
        }
        .navigationTitle("백그라운드 기록")
    }
}
