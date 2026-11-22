import SwiftUI
import DigiWalkerCore

struct WatchHomeView: View {
    private let assets = MonsterAssets.shared

    #if DEBUG
    @State private var debugOffset = 0
    #endif

    var body: some View {
        switch assets.result {
        case .success(let loaded):
            monsterView(loaded)
        case .failure:
            VStack(spacing: 6) {
                Image(systemName: "questionmark.square.dashed").font(.largeTitle)
                Text("몬스터 팩을 불러오지 못했어요")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func monsterView(_ loaded: MonsterAssets.Loaded) -> some View {
        let library = loaded.library
        let starterIndex = library.species.firstIndex { $0.speciesId == library.starterSpeciesId } ?? 0
        #if DEBUG
        let species = library.species.isEmpty ? nil : library.species[(starterIndex + debugOffset) % library.species.count]
        #else
        let species = library.starter
        #endif
        if let species {
            GeometryReader { proxy in
                // 이름·단계 텍스트 공간을 남기고 들어가는 가장 큰 정수 배율 (최대 4)
                let scale = integerPixelScale(
                    spriteSize: species.size,
                    availableWidth: proxy.size.width,
                    availableHeight: proxy.size.height * 0.6
                )
                VStack(spacing: 4) {
                    SpriteView(species: species, pixelSize: scale)
                    Text(species.displayName).font(.headline)
                    Text(species.stage).font(.caption2).foregroundStyle(.secondary)
                    #if DEBUG
                    Text("pack: \(loaded.source.rawValue)\(loaded.skipped.isEmpty ? "" : " (폴백)")")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    #endif
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            #if DEBUG
            .contentShape(Rectangle())
            .onTapGesture { debugOffset += 1 }
            #endif
        } else {
            Text("몬스터 팩을 불러오지 못했어요").font(.footnote).padding()
        }
    }
}

#Preview {
    WatchHomeView()
}
