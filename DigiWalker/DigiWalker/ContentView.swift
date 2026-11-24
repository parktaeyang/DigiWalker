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
                            PartnerPortrait(speciesId: snapshot.monster.speciesId, slot: 128)
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
                    }
                    Section("워치 활동 기록") {
                        if let date = snapshot.observedAt {
                            LabeledContent(date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: snapshot.timeZone ?? .current)) + " 걸음",
                                           value: snapshot.todaySteps?.formatted() ?? "기록 없음")
                        }
                        LabeledContent("누적 인정 걸음", value: snapshot.monster.totalCreditedSteps.formatted())
                        LabeledContent("누적 거리", value: Measurement(value: snapshot.monster.distanceMeters / 1000,
                            unit: UnitLength.kilometers).formatted(.measurement(width: .abbreviated, usage: .asProvided)))
                        LabeledContent("마지막 수신", value: cache.receivedAt.formatted(date: .abbreviated, time: .shortened))
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
