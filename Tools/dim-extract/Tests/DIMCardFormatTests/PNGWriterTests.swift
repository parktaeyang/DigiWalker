import Foundation
import ImageIO
import Testing
@testable import DIMCardFormat

struct PNGWriterTests {
    @Test func checksumVectors() {
        #expect(PNGWriter.crc32(Array("123456789".utf8)) == 0xCBF43926)
        #expect(PNGWriter.crc32([]) == 0)
        #expect(PNGWriter.adler32(Array("Wikipedia".utf8)) == 0x11E60398)
        #expect(PNGWriter.adler32([]) == 1)
    }

    @Test func rejectsBadDimensions() {
        #expect(throws: PNGWriterError.invalidDimensions) { try PNGWriter.encode(width: 0, height: 1, rgba: []) }
        #expect(throws: PNGWriterError.invalidDimensions) { try PNGWriter.encode(width: 1, height: 1, rgba: [0, 0, 0]) }
    }

    static func decode(_ data: Data) throws -> (w: Int, h: Int, rgba: [UInt8]) {
        let src = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        let w = image.width, h = image.height
        // Straight alpha is not available from CGContext, so only fully opaque or fully clear pixels are compared.
        let ctx = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let data = try #require(ctx.data)
        return (w, h, Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: w * h * 4)))
    }

    @Test(arguments: [true, false]) func roundTripsThroughImageIO(compress: Bool) throws {
        let rgba: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255,
                             0, 0, 0, 0, 8, 16, 24, 255, 255, 255, 255, 255]
        let png = try PNGWriter.encode(width: 3, height: 2, rgba: rgba, compress: compress)
        let out = try Self.decode(png)
        #expect(out.w == 3 && out.h == 2)
        #expect(out.rgba == rgba)
    }

    @Test func storedBlocksSplitLargeInput() throws {
        let rgba = [UInt8](repeating: 7, count: 200 * 200 * 4)
        let png = try PNGWriter.encode(width: 200, height: 200, rgba: rgba, compress: false)
        let out = try Self.decode(png)
        #expect(out.w == 200 && out.rgba.count == rgba.count)
    }
}
