import SwiftUI
import DigiWalkerCore

extension RGBA8 {
    var color: Color {
        Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

/// 디코딩된 도트 몬스터를 Canvas로 그린다. 픽셀 크기는 정수 포인트.
struct SpriteView: View {
    let species: DecodedSpecies
    var animationName: String = "idle"
    var pixelSize: Int = 4

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        if let animation = species.animations[animationName], !animation.frames.isEmpty {
            let side = CGFloat(species.size * pixelSize)
            TimelineView(.animation(minimumInterval: animation.frameDuration, paused: isLuminanceReduced)) { context in
                let index = frameIndex(
                    at: context.date, frameDuration: animation.frameDuration,
                    frameCount: animation.frames.count, paused: isLuminanceReduced
                )
                let frame = animation.frames[index]
                Canvas { gc, _ in
                    let p = CGFloat(pixelSize)
                    for run in frame.runs {
                        let rect = CGRect(x: CGFloat(run.x) * p, y: CGFloat(run.y) * p, width: CGFloat(run.length) * p, height: p)
                        gc.fill(Path(rect), with: .color(run.color.color))
                    }
                }
                .frame(width: side, height: side)
            }
            .frame(width: side, height: side)
            .accessibilityLabel(species.displayName)
        }
    }
}
