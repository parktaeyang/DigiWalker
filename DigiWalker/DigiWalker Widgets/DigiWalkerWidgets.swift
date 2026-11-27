import DigiWalkerCore
import SwiftUI
import WidgetKit

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
