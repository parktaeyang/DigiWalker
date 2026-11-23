import DigiWalkerCore
import SwiftUI

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
            if monster.hatchling != nil {
                Text("유년기 I").font(.caption).foregroundStyle(.secondary)
            }
            Text("Lv. \(monster.level) · \(monster.experience) XP")
                .accessibilityIdentifier("partnerGrowth")
        }
    }
}
