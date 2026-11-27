import DigiWalkerCore
import SwiftUI

struct PartnerPortrait: View {
    /// Species with a PNG in this bundle's asset catalog (fallback when no DIM sheet is available).
    static let bundledSpeciesIds: Set<String> = ["digitama", "botamon", "punimon", "poyomon", "starter_acorn"]

    let speciesId: String
    /// Square area in points the portrait is centered in; sprites scale by whole numbers only.
    var slot: CGFloat = 64
    var animated = false
    /// Undiscovered dex entries: always the placeholder, never the real sprite or name.
    var concealed = false
    /// Scale by whole device pixels instead of whole points (e.g. 3 device px per sprite px = 1.5pt at 2x),
    /// so the sprite can fill more of the slot while staying nearest-neighbor sharp.
    var devicePixelScaling = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var phase
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var frames: [String] {
        if speciesId == "starter_acorn" {
            return ["monster_idle_0", "monster_idle_1", "monster_idle_0", "monster_idle_2"]
        }
        return ["\(speciesId)_idle_0", "\(speciesId)_idle_1"]
    }

    /// Whole-number scale: max(1, floor(slot / largest side)).
    static func scale(slot: CGFloat, pixelSize: Int) -> Int {
        max(1, Int((slot / CGFloat(max(1, pixelSize))).rounded(.down)))
    }

    /// Points per sprite pixel: a whole number of points, or of device pixels with `devicePixelScaling`.
    static func pointsPerPixel(slot: CGFloat, pixelSize: Int, displayScale: CGFloat, devicePixels: Bool) -> CGFloat {
        guard devicePixels, displayScale >= 1 else { return CGFloat(scale(slot: slot, pixelSize: pixelSize)) }
        return CGFloat(scale(slot: slot * displayScale, pixelSize: pixelSize)) / displayScale
    }

    private func unit(_ pixelSize: Int) -> CGFloat {
        Self.pointsPerPixel(slot: slot, pixelSize: pixelSize, displayScale: displayScale, devicePixels: devicePixelScaling)
    }

    var body: some View {
        Group {
            // 1. DIM sheet in PrivateAssets, 2. repository PNG, 3. placeholder.
            if concealed {
                placeholder(label: "미발견")
            } else if let dim = DIMSpriteStore.shared.idleFrames(for: speciesId) {
                animatedImage(count: dim.idle.count) { index in
                    let k = unit(max(dim.spec.frameWidth, dim.spec.frameHeight))
                    Image(decorative: dim.idle[index], scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: CGFloat(dim.spec.frameWidth) * k, height: CGFloat(dim.spec.frameHeight) * k)
                }
            } else if Self.bundledSpeciesIds.contains(speciesId) {
                animatedImage(count: frames.count) { index in
                    let side = 32 * unit(32)
                    Image(frames[index])
                        .interpolation(.none)
                        .resizable()
                        .frame(width: side, height: side)
                }
            } else {
                placeholder(label: SpeciesCatalog.info(id: speciesId)?.name ?? speciesId)
            }
        }
        .frame(width: slot, height: slot)
    }

    private func placeholder(label: String) -> some View {
        Image(systemName: "questionmark.square.dashed")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.secondary)
            .padding(slot / 8)
            .accessibilityLabel(label)
    }

    private func animatedImage<Content: View>(count: Int, @ViewBuilder content: @escaping (Int) -> Content) -> some View {
        let paused = !animated || phase != .active || dimmed || reduceMotion
        return TimelineView(.animation(minimumInterval: 0.5, paused: paused)) { context in
            content(frameIndex(at: context.date, frameDuration: 0.5, frameCount: count, paused: paused))
                .accessibilityHidden(true)
        }
    }
}
