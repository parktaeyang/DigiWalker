import DigiWalkerCore
import SwiftUI
import WidgetKit

struct PhonePartnerWidgetView: View {
    let entry: PartnerEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(family == .systemSmall ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear),
                                 for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .systemSmall:
                small(snapshot)
            case .accessoryRectangular:
                HStack(spacing: 6) {
                    PartnerSprite(speciesId: snapshot.speciesId, originalArtOnly: entry.originalArtOnly)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(snapshot.name).font(.headline).lineLimit(1)
                        Text(snapshot.progressText).font(.caption2).lineLimit(2).privacySensitive()
                    }
                    Spacer(minLength: 0)
                }
            case .accessoryInline:
                Text(snapshot.inlineText).privacySensitive()
            default:
                ZStack {
                    AccessoryWidgetBackground()
                    PartnerSprite(speciesId: snapshot.speciesId, originalArtOnly: entry.originalArtOnly)
                        .padding(6)
                }
                .accessibilityElement(children: .ignore)
                // The label stays the name only: the step text would otherwise be read out on a locked screen.
                .accessibilityLabel(snapshot.name)
            }
        } else {
            switch family {
            case .systemSmall:
                Text("iPhone에서 DigiWalker를 열어 주세요")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            case .accessoryRectangular:
                Text("DigiWalker 앱을 열어 주세요").font(.caption)
            case .accessoryInline:
                Text("DigiWalker · 앱을 열어 주세요")
            default:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "questionmark")
                }
            }
        }
    }

    private func small(_ snapshot: WidgetSnapshot) -> some View {
        VStack(spacing: 2) {
            PartnerSprite(speciesId: snapshot.speciesId, originalArtOnly: entry.originalArtOnly)
                .frame(width: 72, height: 64)
            Text(snapshot.name).font(.headline).lineLimit(1)
            Text(snapshot.progressText).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                .privacySensitive()
            // The copy changes only when the iPhone app receives a snapshot, so the time shows how old it is.
            Text(Self.receivedText(snapshot.updatedAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// "M/d HH:mm 수신": always with the date and a fixed 24-hour clock. The timeline never expires, so "today" could
    /// not be kept right, and a 12-hour clock would not tell 06:00 from 18:00.
    static func receivedText(_ received: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "M/d HH:mm"
        return "\(formatter.string(from: received)) 수신"
    }
}

struct DigiWalkerPhonePartnerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.widgetKind, provider: PartnerProvider()) { entry in
            PhonePartnerWidgetView(entry: entry)
        }
        .configurationDisplayName("DigiWalker")
        .description("지금 함께하는 디지몬과 다음 진화까지 남은 걸음을 보여 줘요. iPhone 앱이 워치 기록을 받을 때 바뀌어요. 최신 상태는 앱을 열어 확인하세요.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct DigiWalkerPhoneWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DigiWalkerPhonePartnerWidget()
    }
}
