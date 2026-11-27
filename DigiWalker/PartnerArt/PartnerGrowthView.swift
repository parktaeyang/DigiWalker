import DigiWalkerCore
import SwiftUI

enum StageLabel {
    static let names = ["유년기 I", "유년기 II", "성장기", "성숙기", "완전체", "궁극체"]
    static func text(_ stage: Int) -> String { names.indices.contains(stage) ? names[stage] : "" }
}

struct PartnerGrowthView: View {
    let monster: Monster
    /// False when the cache comes from a watch app too old to take a new-egg request: the hint would promise
    /// something the user cannot do.
    var offersNewEgg = true

    /// The one-line note at the last stage, or nil when the "steps until a new egg" countdown applies. Without a
    /// watch that takes requests there is no new egg to count down to, so only the plain stage name is shown.
    static func finalStageHint(monster: Monster, offersNewEgg: Bool) -> String? {
        guard offersNewEgg else { return "최종 단계" }
        return monster.canStartNewEgg ? "새 알을 키울 수 있어요" : nil
    }

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
            if let stage = monster.stage {
                if stage + 1 < EvolutionCard.stageCount {
                    let from = EvolutionCard.requiredSteps(stage: stage)
                    let next = EvolutionCard.requiredSteps(stage: stage + 1)
                    VStack(spacing: 4) {
                        Text("다음 진화까지 \(max(0, next - monster.totalCreditedSteps).formatted())걸음").font(.caption)
                            .accessibilityIdentifier("partnerGrowth")
                        ProgressView(value: Double(min(max(monster.totalCreditedSteps - from, 0), next - from)),
                                     total: Double(next - from))
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 128)
                            .accessibilityHidden(true)
                    }
                } else if let hint = Self.finalStageHint(monster: monster, offersNewEgg: offersNewEgg) {
                    Text(hint).font(.caption)
                        .accessibilityIdentifier("partnerGrowth")
                } else {
                    // Last stage: count from the ultimate threshold to the new egg threshold.
                    let from = EvolutionCard.requiredSteps(stage: stage)
                    let next = Monster.stepsForNewEgg
                    VStack(spacing: 4) {
                        Text("새 알까지 \(max(0, next - monster.totalCreditedSteps).formatted())걸음").font(.caption)
                            .accessibilityIdentifier("partnerGrowth")
                        ProgressView(value: Double(min(max(monster.totalCreditedSteps - from, 0), next - from)),
                                     total: Double(next - from))
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 128)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }
}
