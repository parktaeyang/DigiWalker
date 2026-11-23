import DigiWalkerCore
import SwiftUI

struct PartnerPortrait: View {
    let speciesId: String
    var animated = false
    @Environment(\.scenePhase) private var phase
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var frames: [String] {
        if speciesId == "starter_acorn" {
            return ["monster_idle_0", "monster_idle_1", "monster_idle_0", "monster_idle_2"]
        }
        return ["\(speciesId)_idle_0", "\(speciesId)_idle_1"]
    }

    var body: some View {
        let paused = !animated || phase != .active || dimmed || reduceMotion
        TimelineView(.animation(minimumInterval: 0.5, paused: paused)) { context in
            let index = frameIndex(at: context.date, frameDuration: 0.5, frameCount: frames.count, paused: paused)
            Image(frames[index])
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        }
    }
}
