import DigiWalkerCore
import SwiftUI
import WidgetKit

// This target defaults to MainActor isolation. WidgetKit calls the provider from its own queues, so the
// provider and the entry are explicitly nonisolated; only views touch MainActor state (the sprite cache).

nonisolated struct PartnerEntry: TimelineEntry {
    let date: Date
    /// Nil until the watch app has written a copy (or when it is unreadable).
    let snapshot: WidgetSnapshot?
    /// Gallery and placeholder entries use only the repository's original art.
    let originalArtOnly: Bool
}

nonisolated struct PartnerProvider: TimelineProvider {
    func placeholder(in context: Context) -> PartnerEntry { Self.sample }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (PartnerEntry) -> Void) {
        completion(context.isPreview ? Self.sample : Self.current())
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<PartnerEntry>) -> Void) {
        // The watch app asks for reloads itself, so a readable copy never expires on its own. An unreadable one
        // (not written yet, or briefly locked) is tried again later.
        let entry = Self.current()
        let retry = WidgetTimelineRetry.nextRefresh(copyReadable: entry.snapshot != nil, now: .now)
        completion(Timeline(entries: [entry], policy: retry.map { .after($0) } ?? .never))
    }

    private static var sample: PartnerEntry {
        PartnerEntry(date: .now, snapshot: WidgetSnapshot(state: GameState(), now: .now), originalArtOnly: true)
    }

    private static func current() -> PartnerEntry {
        PartnerEntry(date: .now, snapshot: readSnapshot(), originalArtOnly: false)
    }

    private static func readSnapshot() -> WidgetSnapshot? {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroupIdentifier)?
            .appending(path: WidgetSnapshot.fileName),
              let snapshot = (try? StateFile<WidgetSnapshot>(url: url).load()) ?? nil,
              WidgetSnapshot.supportedSchemaVersions.contains(snapshot.schemaVersion) else { return nil }
        return snapshot
    }
}

extension WidgetSnapshot {
    var progressText: String {
        switch progress {
        case .hatch(let remaining): "부화까지 \(remaining.formatted())걸음"
        case .evolution(let remaining): "다음 진화까지 \(remaining.formatted())걸음"
        case .newEgg(let remaining): "새 알까지 \(remaining.formatted())걸음"
        case .newEggReady: "새 알 준비"
        case .unknown: "단계 정보를 확인 중"
        }
    }

    var shortProgressText: String {
        switch progress {
        case .hatch(let remaining), .evolution(let remaining), .newEgg(let remaining): "\(remaining.formatted())걸음"
        case .newEggReady: "새 알"
        case .unknown: "—"
        }
    }

    var inlineText: String {
        switch progress {
        case .hatch(let remaining), .evolution(let remaining), .newEgg(let remaining):
            "\(name) · \(remaining.formatted())걸음 남음"
        case .newEggReady: "\(name) · 새 알 준비"
        case .unknown: name
        }
    }
}

/// One idle frame, drawn with a whole number of device pixels per image pixel and nearest-neighbor sampling.
/// Falls back to the repository's original art, then to a question mark.
struct PartnerSprite: View {
    let speciesId: String
    let originalArtOnly: Bool
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            VStack {
                content(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    @ViewBuilder
    private func content(width: CGFloat, height: CGFloat) -> some View {
        if !originalArtOnly, let dim = DIMSpriteStore.shared.idleFrames(for: speciesId), let frame = dim.idle.first {
            let k = Self.factor(width: width, height: height, pixels: (dim.spec.frameWidth, dim.spec.frameHeight),
                                scale: displayScale)
            Image(decorative: frame, scale: 1)
                .interpolation(.none)
                .antialiased(false)
                .resizable()
                .widgetAccentedRenderingMode(.fullColor)
                .frame(width: Double(dim.spec.frameWidth * k) / displayScale,
                       height: Double(dim.spec.frameHeight * k) / displayScale)
        } else if PartnerPortrait.bundledSpeciesIds.contains(speciesId) {
            let k = Self.factor(width: width, height: height, pixels: (32, 32), scale: displayScale)
            Image(speciesId == "starter_acorn" ? "monster_idle_0" : "\(speciesId)_idle_0")
                .interpolation(.none)
                .antialiased(false)
                .resizable()
                .widgetAccentedRenderingMode(.fullColor)
                .frame(width: Double(32 * k) / displayScale, height: Double(32 * k) / displayScale)
        } else {
            Image(systemName: "questionmark.square.dashed")
                .resizable()
                .scaledToFit()
                .padding(min(width, height) / 8)
        }
    }

    private static func factor(width: CGFloat, height: CGFloat, pixels: (Int, Int), scale: CGFloat) -> Int {
        min(PixelScaling.factor(availablePoints: Double(width), spritePixels: pixels.0, displayScale: Double(scale)),
            PixelScaling.factor(availablePoints: Double(height), spritePixels: pixels.1, displayScale: Double(scale)))
    }
}

struct PartnerWidgetView: View {
    let entry: PartnerEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(.clear, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .accessoryRectangular:
                HStack(spacing: 6) {
                    PartnerSprite(speciesId: snapshot.speciesId, originalArtOnly: entry.originalArtOnly)
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(snapshot.name).font(.headline).lineLimit(1)
                        Text(snapshot.progressText).font(.caption2).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
            case .accessoryCorner:
                PartnerSprite(speciesId: snapshot.speciesId, originalArtOnly: entry.originalArtOnly)
                    .padding(2)
                    .widgetLabel { Text(snapshot.shortProgressText) }
            case .accessoryInline:
                Text(snapshot.inlineText)
            default:
                ZStack {
                    AccessoryWidgetBackground()
                    PartnerSprite(speciesId: snapshot.speciesId, originalArtOnly: entry.originalArtOnly)
                        .padding(4)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(snapshot.name)
            }
        } else {
            switch family {
            case .accessoryRectangular:
                Text("DigiWalker 앱을 열어 주세요").font(.caption)
            case .accessoryInline:
                Text("DigiWalker · 앱을 열어 주세요")
            default:
                Image(systemName: "questionmark")
            }
        }
    }
}

struct DigiWalkerPartnerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.widgetKind, provider: PartnerProvider()) { entry in
            PartnerWidgetView(entry: entry)
        }
        .configurationDisplayName("DigiWalker")
        .description("지금 함께하는 디지몬과 다음 진화까지 남은 걸음을 보여 줘요.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

@main
struct DigiWalkerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DigiWalkerPartnerWidget()
    }
}
