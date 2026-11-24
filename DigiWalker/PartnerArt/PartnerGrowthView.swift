import DigiWalkerCore
import SwiftUI

enum StageLabel {
    static let names = ["유년기 I", "유년기 II", "성장기", "성숙기", "완전체", "궁극체"]
    static func text(_ stage: Int) -> String { names.indices.contains(stage) ? names[stage] : "" }
}

struct PartnerGrowthView: View {
    let monster: Monster

    var body: some View {
        if monster.isEgg {
            VStack(spacing: 4) {
                Text("부화 \(monster.totalCreditedSteps) / \(Monster.stepsToHatch)걸음")
                    .font(.subheadline)
                    .accessibilityIdentifier("partnerGrowth")
                ProgressView(value: Double(monster.totalCreditedSteps), total: Double(Monster.stepsToHatch))
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 128)
                    .accessibilityHidden(true)
            }
        } else {
            // A v1 cache has no cardId; show the baby label by species only, without assigning a card.
            let legacyBaby = ["botamon", "punimon", "poyomon"].contains(monster.speciesId)
            if let stage = monster.stage ?? (legacyBaby ? 0 : nil) {
                Text(StageLabel.text(stage)).font(.caption).foregroundStyle(.secondary)
            }
            Text("Lv. \(monster.level) · \(monster.experience) XP")
                .accessibilityIdentifier("partnerGrowth")
            if let stage = monster.stage {
                if stage + 1 < EvolutionCard.stageCount {
                    let from = EvolutionCard.requiredSteps(stage: stage)
                    let next = EvolutionCard.requiredSteps(stage: stage + 1)
                    VStack(spacing: 4) {
                        Text("다음 진화까지 \(max(0, next - monster.totalCreditedSteps).formatted())걸음").font(.caption)
                        ProgressView(value: Double(min(max(monster.totalCreditedSteps - from, 0), next - from)),
                                     total: Double(next - from))
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 128)
                            .accessibilityHidden(true)
                    }
                } else {
                    Text("최종 단계").font(.caption)
                }
            }
        }
    }
}
