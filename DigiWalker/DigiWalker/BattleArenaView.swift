import DigiWalkerCore
import SwiftUI

/// Two dots facing each other, the three-round pick, and the result.
struct BattleArenaView: View {
    let flow: BattleFlow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let e = flow.encounter {
            List {
                Section { facing(e).frame(maxWidth: .infinity) }
                if e.isFinished { result(e) } else { picking(e) }
            }
            .navigationTitle("친선 배틀")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// DIM dots look to the left, so my dot (on the left) is mirrored to face the opponent.
    private func facing(_ e: BattleFlow.Encounter) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack {
                PartnerPortrait(speciesId: e.mine.speciesId, slot: 120, animated: true, devicePixelScaling: true)
                    .scaleEffect(x: -1, y: 1)
                Text(e.mine.name).font(.subheadline.bold())
            }
            VStack {
                PartnerPortrait(speciesId: e.opponent.speciesId, slot: 120, animated: true, devicePixelScaling: true)
                Text(SpeciesCatalog.info(id: e.opponent.speciesId)?.name ?? e.opponent.name).font(.subheadline.bold())
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func picking(_ e: BattleFlow.Encounter) -> some View {
        let session = e.session
        Section {
            if e.isAwaitingExtraRound {
                Text("아직 승부가 나지 않았어요 — 한 판 더!").font(.headline)
                Text(BattleFlow.score(session)).foregroundStyle(.secondary)
                if session.rounds.last?.note == .guardDraw {
                    Text("방어끼리는 비겨요. 공격을 골라 보세요").font(.footnote).foregroundStyle(.orange)
                }
            } else {
                // The first three rounds stay hidden until the battle is over.
                HStack {
                    ForEach(0..<BattleRules.patternLength, id: \.self) { i in
                        Text("\(i + 1)판 \(i < e.picks.count ? "선택함" : "")")
                            .frame(maxWidth: .infinity).padding(6)
                            .background(i < e.picks.count ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                Text("\(e.picks.count + 1)판: 공격 또는 방어를 고르세요").font(.headline)
            }
            HStack {
                Button("공격") { flow.choose(.attack) }.accessibilityIdentifier("battleAttack")
                Button("방어") { flow.choose(.defend) }.accessibilityIdentifier("battleDefend")
            }
            .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func result(_ e: BattleFlow.Encounter) -> some View {
        Section {
            Text(e.session.winner == .me ? "승리!" : "패배…")
                .font(.largeTitle.bold()).frame(maxWidth: .infinity)
                .accessibilityIdentifier("battleResult")
        }
        Section("판별") {
            ForEach(e.session.rounds, id: \.index) { round in
                VStack(alignment: .leading, spacing: 2) {
                    Text(BattleFlow.summary(round))
                    Text(BattleFlow.detail(round)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            ForEach(e.undecidedPicks, id: \.index) { pick in
                VStack(alignment: .leading, spacing: 2) {
                    Text(BattleFlow.undecidedSummary(index: pick.index)).foregroundStyle(.secondary)
                    Text(BattleFlow.undecidedDetail(pick.move)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        Section {
            Button("다시 하기") { flow.rematch() }
            Button("끝내기") { dismiss() }
        }
    }
}
