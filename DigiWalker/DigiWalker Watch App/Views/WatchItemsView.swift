import DigiWalkerCore
import SwiftUI

/// Items held now (found minus used up by locked evolutions), one row per kind. Text only: no item pictures are used.
struct WatchItemsView: View {
    let summaries: [ItemSummary]

    var body: some View {
        List {
            if summaries.isEmpty {
                Text("\(ItemDrop.stepsPerSegment.formatted())걸음마다 아이템을 찾을 수 있어요").font(.footnote)
            }
            ForEach(summaries, id: \.itemId) { summary in
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(ItemCatalog.info(id: summary.itemId)?.name ?? summary.itemId).font(.caption)
                        Spacer()
                        Text("×\(summary.count)").font(.caption.monospacedDigit())
                    }
                    Text("처음 얻은 날 \(summary.firstGrantedAt.formatted(.dateTime.month().day().hour().minute()))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("아이템")
    }
}
