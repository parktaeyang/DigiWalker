import CoreGraphics
import DigiWalkerCore
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import DigiWalker

/// Uses only synthetic sheets generated here, written to a temporary directory.
@MainActor
struct DIMSpriteStoreTests {
    private let space = CGColorSpaceCreateDeviceRGB()
    private let info = CGImageAlphaInfo.premultipliedLast.rawValue

    /// Writes premultiplied RGBA bytes as a PNG. Core Graphics owns the pixel buffer, so no pointer outlives its call.
    private func writePNG(width: Int, height: Int, rgba: [UInt8], to url: URL) throws {
        #expect(rgba.count == width * height * 4)
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: space, bitmapInfo: info))
        let buffer = try #require(context.data).bindMemory(to: UInt8.self, capacity: rgba.count)
        for (i, byte) in rgba.enumerated() { buffer[i] = byte }
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    /// Renders an image into premultiplied RGBA bytes.
    private func bytes(of image: CGImage) throws -> [UInt8] {
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                             bytesPerRow: image.width * 4, space: space, bitmapInfo: info))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let count = image.width * image.height * 4
        let buffer = try #require(context.data).bindMemory(to: UInt8.self, capacity: count)
        return Array(UnsafeBufferPointer(start: buffer, count: count))
    }

    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dim-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Frame f (2x2) holds four distinct pixels, including opaque, half-transparent and fully transparent ones.
    /// Half-transparent colors use 0/128 so the PNG un/premultiply round trip is exact.
    private func framePixels(_ f: Int) -> [[UInt8]] {
        let v = UInt8(10 * (f + 1))
        return [[v, 0, 0, 255], [0, v, 0, 255], [0, 128, 0, 128], [0, 0, 0, 0]]
    }

    @Test func framesKeepOrderAlphaAndExactBytes() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let spec = DIMSpriteSpec(frameWidth: 2, frameHeight: 2, frameCount: 5, idleFrames: [3, 0, 4])
        // One row of five 2x2 frames: pixel (x, y) of frame f sits at column 2f + x.
        var sheet = [UInt8](repeating: 0, count: 10 * 2 * 4)
        for f in 0..<5 {
            let pixels = framePixels(f)
            for y in 0..<2 {
                for x in 0..<2 {
                    let offset = (y * 10 + f * 2 + x) * 4
                    sheet.replaceSubrange(offset..<offset + 4, with: pixels[y * 2 + x])
                }
            }
        }
        let url = dir.appendingPathComponent("sheet.png")
        try writePNG(width: 10, height: 2, rgba: sheet, to: url)
        let frames = try DIMSpriteStore.load(url: url, spec: spec)
        #expect(frames.count == 3)
        for (frame, source) in zip(frames, [3, 0, 4]) {
            #expect(frame.width == 2 && frame.height == 2)
            #expect(try bytes(of: frame) == framePixels(source).flatMap { $0 })
        }
    }

    @Test func storeCachesSlicedIdleFramesByCatalogSpec() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var sheet = [UInt8](repeating: 0, count: 160 * 24 * 4)
        for i in stride(from: 0, to: sheet.count, by: 4) { sheet[i] = 200; sheet[i + 3] = 255 }
        try writePNG(width: 160, height: 24, rgba: sheet, to: dir.appendingPathComponent("botamon.png"))
        let store = DIMSpriteStore(bundle: nil, directory: dir)
        let frames = try #require(store.idleFrames(for: "botamon"))
        #expect(frames.idle.count == 2)
        #expect(frames.idle.allSatisfy { $0.width == 32 && $0.height == 24 })
        #expect(store.idleFrames(for: "botamon") != nil)
    }

    @Test func failuresReturnNilAndAreDistinguished() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let spec = DIMSpriteSpec(frameWidth: 32, frameHeight: 24, frameCount: 5)
        #expect(throws: DIMSpriteLoadFailure.missingFile) {
            try DIMSpriteStore.load(url: dir.appendingPathComponent("none.png"), spec: spec)
        }
        let bad = dir.appendingPathComponent("koromon.png")
        try writePNG(width: 100, height: 24, rgba: [UInt8](repeating: 255, count: 100 * 24 * 4), to: bad)
        #expect(throws: DIMSpriteLoadFailure.invalidSheet(width: 100, height: 24)) {
            try DIMSpriteStore.load(url: bad, spec: spec)
        }
        let junk = dir.appendingPathComponent("agumon.png")
        try Data("not a png".utf8).write(to: junk)
        #expect(throws: DIMSpriteLoadFailure.unreadable) { try DIMSpriteStore.load(url: junk, spec: spec) }
        let store = DIMSpriteStore(bundle: nil, directory: dir)
        #expect(store.idleFrames(for: "koromon") == nil)
        #expect(store.idleFrames(for: "agumon") == nil)
        #expect(store.idleFrames(for: "digitama") == nil)
        #expect(store.idleFrames(for: "unknown_species") == nil)
    }

    @Test func oversizedSheetIsRejected() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let spec = DIMSpriteSpec(frameWidth: 32, frameHeight: 24, frameCount: 5)
        // 192x120 is 6x5 = 30 cells, more than 2x the 5 frames.
        let url = dir.appendingPathComponent("big.png")
        try writePNG(width: 192, height: 120, rgba: [UInt8](repeating: 255, count: 192 * 120 * 4), to: url)
        #expect(throws: DIMSpriteLoadFailure.invalidSheet(width: 192, height: 120)) {
            try DIMSpriteStore.load(url: url, spec: spec)
        }
    }

    @Test func spareCellsWithinTheLimitAreAccepted() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let spec = DIMSpriteSpec(frameWidth: 32, frameHeight: 24, frameCount: 5)
        let url = dir.appendingPathComponent("spare.png")
        try writePNG(width: 192, height: 24, rgba: [UInt8](repeating: 255, count: 192 * 24 * 4), to: url)
        #expect(try DIMSpriteStore.load(url: url, spec: spec).count == 2)
        let grid = dir.appendingPathComponent("grid.png") // 3x2 = 6 cells, still within 10
        try writePNG(width: 96, height: 48, rgba: [UInt8](repeating: 255, count: 96 * 48 * 4), to: grid)
        #expect(try DIMSpriteStore.load(url: grid, spec: spec).count == 2)
    }

    @Test func integerScale() {
        #expect(PartnerPortrait.scale(slot: 64, pixelSize: 64) == 1)
        #expect(PartnerPortrait.scale(slot: 128, pixelSize: 64) == 2)
        #expect(PartnerPortrait.scale(slot: 64, pixelSize: 32) == 2)
        #expect(PartnerPortrait.scale(slot: 50, pixelSize: 64) == 1)
        #expect(PartnerPortrait.scale(slot: 100, pixelSize: 32) == 3)
    }
}
