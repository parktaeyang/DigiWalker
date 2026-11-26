import DigiWalkerCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var sync: PhoneSyncService

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
                            PartnerGrowthView(monster: snapshot.monster)
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
