import DigiWalkerCore
import SwiftUI

struct WatchHomeView: View {
    @ObservedObject var game: WatchGameStore
    #if DEBUG
    @State private var previewIndex = 0
    #endif
    @Environment(\.scenePhase) private var phase
    /// Keeps the alert and the new-egg dialog from overlapping.
    @State private var flow = AlertFlow()
    @State private var showingLog = false
    @State private var showingItems = false

    var body: some View {
        ScrollView {
            VStack(spacing: 5) {
                if let state = game.state {
                    portrait(state.monster)
                    Text(state.monster.name).font(.headline)
                    PartnerGrowthView(monster: state.monster)
                    if state.monster.canStartNewEgg {
                        Button("새 알 키우기") { game.requestNewEggConfirmation() }
                            .font(.caption)
                            .accessibilityIdentifier("newEggButton")
                    }
                    // What is held now (grants minus uses), not how many were ever found.
                    let held = state.itemSummaries.reduce(0) { $0 + $1.count }
                    if held == 0 {
                        Text("\(ItemDrop.stepsPerSegment.formatted())걸음마다 아이템을 찾을 수 있어요")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Button("아이템 \(held)개") { showingItems = true }
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
                    Text("앱을 닫아 두어도 부화·진화·아이템·새 알을 알려 드려요. 알림은 수십 분에서 1시간 정도 늦을 수 있어요.")
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
        .alert(flow.presented?.title ?? "", isPresented: Binding(
            get: { flow.presented != nil },
            set: { if !$0 { closeAlert() } }
        )) {
            if let offer = flow.presented, offer.kind == .newEggReady {
                // Closing the alert any other way keeps the finished partner.
                // The dialog opens once the alert is gone (see the dialog binding), in place of the next alert.
                Button("새 알 키우기") { game.requestNewEggConfirmation(for: offer.monsterId) }
                Button("궁극체 유지", role: .cancel) { }
            } else {
                Button("확인", role: .cancel) { }
            }
        } message: {
            Text(flow.presented?.body ?? "")
        }
        // First presentation only; the next queued event is presented by closeAlert after its pause.
        .onChange(of: game.presentableAlerts, initial: true) { _, _ in
            flow.present(game.pendingAlert, dialogWanted: game.confirmingNewEgg)
        }
        // A finished partner's offer disappears when its egg was started (e.g. a request from the iPhone).
        .onChange(of: game.alerts) { _, queue in
            flow.dropOfferIfGone(from: queue)
        }
        // After the dialog goes away the queued alerts continue.
        .onChange(of: game.confirmingNewEgg) { _, wanted in
            flow.present(game.pendingAlert, dialogWanted: wanted)
        }
        .task(id: phase) {
            if phase == .active { await game.refresh() }
        }
        .confirmationDialog("정말 새 알을 키울까요?", isPresented: Binding(
            get: { game.confirmingNewEgg && flow.dialogMayShow },
            set: { if !$0 { game.cancelNewEggConfirmation() } }
        ), titleVisibility: .visible) {
            if let monster = game.state?.monster, game.confirmingNewEgg {
                Button("새 알 키우기", role: .destructive) {
                    let target = monster.id
                    Task { await game.startNewEgg(target: target) }
                }
            }
            Button("취소", role: .cancel) { }
        } message: {
            if let name = game.state?.monster.name {
                Text("\(name)\(KoreanParticle.topic(name)) 도감에 남습니다")
            }
        }
        .onAppear { game.loadWakeLog() }
        .sheet(isPresented: $showingLog) { BackgroundLogView(entries: game.wakeData.entries) }
        .sheet(isPresented: $showingItems) {
            if let state = game.state { WatchItemsView(summaries: state.itemSummaries) }
        }
    }

    private func closeAlert() {
        guard let shown = flow.close() else { return }
        game.dismissAlert(id: shown.id)
        // The next step (a wanted dialog, else the next queued event) waits until this alert has fully gone away.
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            flow.pauseEnded(next: game.pendingAlert, dialogWanted: game.confirmingNewEgg)
        }
    }

    @ViewBuilder
    private func portrait(_ monster: Monster) -> some View {
        // starter_acorn still goes through MonsterAssets (private pack) first.
        if monster.speciesId != "starter_acorn", DIMSpriteStore.shared.idleFrames(for: monster.speciesId) != nil
            || PartnerPortrait.bundledSpeciesIds.contains(monster.speciesId) {
            PartnerPortrait(speciesId: monster.speciesId, slot: 96, animated: true, devicePixelScaling: true)
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
            PartnerPortrait(speciesId: monster.speciesId, slot: 96, animated: true, devicePixelScaling: true)
        }
    }

    @ViewBuilder
    private func sprite(_ species: DecodedSpecies, source: MonsterAssets.Source) -> some View {
        if source == .starterPack && species.speciesId == "starter_acorn" {
            PartnerPortrait(speciesId: species.speciesId, slot: 96, animated: true, devicePixelScaling: true)
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
