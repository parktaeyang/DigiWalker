import DigiWalkerCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var sync: PhoneSyncService
    @State private var confirmingNewEgg = false
    /// The partner the dialog was opened for; the request goes to this one even if the cache has changed since.
    @State private var newEggTarget: UUID?

    var body: some View {
        NavigationStack {
            List {
                if let cache = sync.cache {
                    let snapshot = cache.snapshot
                    Section {
                        VStack(spacing: 8) {
                            PartnerPortrait(speciesId: snapshot.monster.speciesId, slot: 128, animated: true)
                            Text(snapshot.monster.name).font(.title.bold())
                            if let card = snapshot.monster.cardId, let title = DexModel.cardTitles[card] {
                                Text(title).font(.caption).foregroundStyle(.secondary)
                            }
                            let newEgg = sync.newEggStatus
                            PartnerGrowthView(monster: snapshot.monster, offersNewEgg: Self.offersNewEgg(snapshot))
                            NewEggControls(status: newEgg, open: { newEggTarget = snapshot.monster.id; confirmingNewEgg = true },
                                           cancel: { sync.cancelNewEggRequest() })
                        }
                        .frame(maxWidth: .infinity)
                        let dex = DexModel(snapshot: snapshot)
                        NavigationLink("도감 · \(dex.discoveredCount) / \(dex.totalCount)") {
                            DexView(snapshot: snapshot)
                        }
                        let items = ItemModel(snapshot: snapshot)
                        NavigationLink(items.synced ? "아이템 · 보유 종류 \(items.ownedKinds) / \(items.totalKinds)" : "아이템") {
                            ItemView(snapshot: snapshot)
                        }
                        NavigationLink("배틀하기") { BattleView(snapshot: snapshot) }
                            .accessibilityIdentifier("battleLink")
                    }
                    Section("워치 활동 기록") {
                        if let date = snapshot.observedAt {
                            LabeledContent(DisplayFormat.day(date, timeZone: snapshot.timeZone) + " 걸음",
                                           value: snapshot.todaySteps?.formatted() ?? "기록 없음")
                        }
                        LabeledContent("누적 인정 걸음", value: snapshot.monster.totalCreditedSteps.formatted())
                        LabeledContent("누적 거리", value: DisplayFormat.distance(meters: snapshot.monster.distanceMeters))
                        LabeledContent("마지막 수신", value: DisplayFormat.dateTime(cache.receivedAt))
                    }
                } else {
                    ContentUnavailableView("파트너를 기다리는 중", systemImage: "applewatch",
                        description: Text("페어링한 워치에서 DigiWalker를 열면 파트너의 성장 기록이 여기에 표시돼요."))
                }
                Text(sync.status).font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("내 파트너")
            .confirmationDialog("정말 새 알을 키울까요?", isPresented: $confirmingNewEgg, titleVisibility: .visible) {
                Button("새 알 키우기", role: .destructive) {
                    if let target = newEggTarget { sync.requestNewEgg(target: target) }
                    newEggTarget = nil
                }
                Button("취소", role: .cancel) { newEggTarget = nil }
            } message: {
                if let name = sync.cache?.snapshot.monster.name, Self.dialogStillValid(target: newEggTarget, cached: sync.cache?.snapshot.monster.id) {
                    Text("\(name)\(KoreanParticle.topic(name)) 도감에 남습니다")
                }
            }
            .onChange(of: sync.cache?.snapshot.monster.id) { _, cachedId in
                if !Self.dialogStillValid(target: newEggTarget, cached: cachedId) {
                    confirmingNewEgg = false
                    newEggTarget = nil
                }
            }
        }
    }

    /// False once the cache shows another partner than the one the dialog was opened for.
    static func dialogStillValid(target: UUID?, cached: UUID?) -> Bool {
        target != nil && target == cached
    }

    /// Only a v4 cache comes from a watch that takes new-egg requests; below that neither the hint nor the
    /// countdown to a new egg is shown.
    static func offersNewEgg(_ snapshot: MonsterSnapshot) -> Bool {
        snapshot.schemaVersion >= 4
    }
}

/// The small button under the partner, or the waiting note with a way to cancel. Shows nothing when no new egg is possible.
struct NewEggControls: View {
    let status: NewEggRequestStatus
    let open: () -> Void
    let cancel: () -> Void

    var body: some View {
        switch status {
        case .hidden:
            EmptyView()
        case .needsWatchUpdate:
            Text("워치 앱을 업데이트해 주세요").font(.caption).foregroundStyle(.secondary)
        case .available:
            Button("새 알 키우기", action: open)
                .buttonStyle(.bordered).controlSize(.small)
                .accessibilityIdentifier("newEggButton")
        case .notConnected:
            Text(NewEggControls.message(for: status)).font(.caption).foregroundStyle(.secondary)
        case .queued, .delivered, .failed:
            VStack(spacing: 4) {
                Text(NewEggControls.message(for: status)).font(.caption).foregroundStyle(.secondary)
                Button(NewEggControls.cancelTitle(for: status), role: .destructive, action: cancel)
                    .buttonStyle(.bordered).controlSize(.small)
                    .accessibilityIdentifier("cancelNewEggButton")
            }
        }
    }

    /// Only a queued request can still be stopped; later the button just clears the note on the iPhone.
    static func cancelTitle(for status: NewEggRequestStatus) -> String {
        status == .queued ? "요청 취소" : "대기 표시 지우기"
    }

    static func message(for status: NewEggRequestStatus) -> String {
        switch status {
        case .queued: "워치에 연결되면 시작됩니다"
        case .delivered: "이미 워치에 전달됐어요. 워치에서 새 알이 시작될 수 있어요"
        case .failed: "요청을 보내지 못했어요. 대기 표시를 지운 뒤 다시 시도해 주세요"
        case .notConnected: "워치와 연결을 확인해 주세요"
        case .hidden, .needsWatchUpdate, .available: ""
        }
    }
}

/// 기기 지역 설정과 관계없이 한국어 형식으로 표시한다.
enum DisplayFormat {
    static let korean = Locale(identifier: "ko_KR")

    /// 예: 2026년 11월 25일
    static func day(_ date: Date, timeZone: TimeZone?) -> String {
        date.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: korean, timeZone: timeZone ?? .current))
    }

    /// 예: 2026. 11. 25. 오전 2:23
    static func dateTime(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .numeric, time: .shortened, locale: korean))
    }

    /// 1km 미만은 미터 정수, 이상은 킬로미터 소수 둘째 자리. 예: 66m, 1.23km
    static func distance(meters: Double) -> String {
        guard meters.isFinite, meters > 0 else { return "0m" }
        let wholeMeters = meters.rounded()
        if wholeMeters < 1000 {
            return "\(Int(wholeMeters).formatted(.number.locale(korean)))m"
        }
        return "\((meters / 1000).formatted(.number.precision(.fractionLength(2)).locale(korean)))km"
    }
}
