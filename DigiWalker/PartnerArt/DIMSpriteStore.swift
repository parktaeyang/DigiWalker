import CoreGraphics
import DigiWalkerCore
import Foundation
import ImageIO

/// Idle frames cut from a user-provided DIM sheet (`PrivateAssets/dim/<speciesId>.png`).
struct DIMFrames {
    let spec: DIMSpriteSpec
    let idle: [CGImage]
}

enum DIMSpriteLoadFailure: Error, Equatable {
    case missingFile
    case unreadable
    case invalidSheet(width: Int, height: Int)
    case badIdleFrames
}

/// Loads sheets from the bundle (or a directory, for tests) and caches the result per species, including failures.
@MainActor
final class DIMSpriteStore {
    static let shared = DIMSpriteStore()

    private let bundle: Bundle?
    private let directory: URL?
    private var cache: [String: DIMFrames?] = [:]

    init(bundle: Bundle? = .main, directory: URL? = nil) {
        self.bundle = bundle
        self.directory = directory
    }

    func idleFrames(for speciesId: String) -> DIMFrames? {
        if let cached = cache[speciesId] { return cached }
        var frames: DIMFrames?
        if let spec = SpeciesCatalog.info(id: speciesId)?.dimSprite {
            do {
                frames = DIMFrames(spec: spec, idle: try Self.load(url: fileURL(for: speciesId), spec: spec))
            } catch {
                #if DEBUG
                // missingFile is the normal state while PrivateAssets is empty; the others point at a bad sheet.
                print("DIMSpriteStore: \(speciesId) -> \(error)")
                #endif
            }
        }
        cache[speciesId] = .some(frames)
        return frames
    }

    private func fileURL(for speciesId: String) throws -> URL {
        if let directory {
            return directory.appendingPathComponent("\(speciesId).png")
        }
        guard let url = bundle?.url(forResource: speciesId, withExtension: "png", subdirectory: "PrivateAssets/dim") else {
            throw DIMSpriteLoadFailure.missingFile
        }
        return url
    }

    /// Cuts the idle frames out of the sheet without touching pixels, alpha or size.
    nonisolated static func load(url: URL, spec: DIMSpriteSpec) throws -> [CGImage] {
        guard FileManager.default.fileExists(atPath: url.path) else { throw DIMSpriteLoadFailure.missingFile }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw DIMSpriteLoadFailure.unreadable }
        let rects: [SheetFrameRect]
        do {
            rects = try SheetSlicing.frames(imageWidth: image.width, imageHeight: image.height, spec: spec)
        } catch {
            throw DIMSpriteLoadFailure.invalidSheet(width: image.width, height: image.height)
        }
        // Resource limit, separate from the slicing contract (spare cells are fine): at most 2x the frame count in
        // cells. Division keeps this free of overflow.
        let columns = image.width / spec.frameWidth, rows = image.height / spec.frameHeight
        guard rows <= 2 * spec.frameCount, columns <= 2 * spec.frameCount / max(rows, 1) else {
            throw DIMSpriteLoadFailure.invalidSheet(width: image.width, height: image.height)
        }
        guard !spec.idleFrames.isEmpty, spec.idleFrames.allSatisfy({ rects.indices.contains($0) }) else {
            throw DIMSpriteLoadFailure.badIdleFrames
        }
        return try spec.idleFrames.map { index in
            let rect = rects[index]
            guard let frame = image.cropping(to: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)) else {
                throw DIMSpriteLoadFailure.unreadable
            }
            return frame
        }
    }
}
