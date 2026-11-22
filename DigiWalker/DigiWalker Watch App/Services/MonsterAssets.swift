import Foundation
import DigiWalkerCore

/// 번들에서 PrivateAssets, StarterPack 순서로 팩을 찾아 한 번 로드한다.
struct MonsterAssets {
    enum Source: String {
        case privatePack = "PrivateAssets"
        case starterPack = "StarterPack"
    }

    struct Loaded {
        let library: SpriteLibrary
        let source: Source
        let skipped: [SpritePackSkip]
    }

    let result: Result<Loaded, SpritePackResolutionFailure>

    static let shared = MonsterAssets.load()

    static func load(bundle: Bundle = .main) -> MonsterAssets {
        let sources: [Source] = [.privatePack, .starterPack]
        let candidates: [(Source, URL)] = sources.compactMap { source in
            bundle.url(forResource: "pack", withExtension: "json", subdirectory: source.rawValue)
                .map { (source, $0.deletingLastPathComponent()) }
        }
        do {
            let resolution = try SpritePackResolver.resolve(candidates: candidates.map(\.1))
            #if DEBUG
            if let first = resolution.skipped.first {
                print("[MonsterAssets] 건너뜀: \(first.directory.lastPathComponent) - \(first.reason)")
            }
            #endif
            let source = candidates.first { $0.1 == resolution.sourceDirectory }?.0 ?? .starterPack
            return MonsterAssets(result: .success(Loaded(library: resolution.library, source: source, skipped: resolution.skipped)))
        } catch let failure as SpritePackResolutionFailure {
            return MonsterAssets(result: .failure(failure))
        } catch {
            return MonsterAssets(result: .failure(SpritePackResolutionFailure(skipped: [])))
        }
    }
}
