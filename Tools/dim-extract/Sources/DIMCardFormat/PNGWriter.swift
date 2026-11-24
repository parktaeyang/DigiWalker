import Compression
import Foundation

public enum PNGWriterError: Error, Equatable {
    case invalidDimensions
}

/// Minimal RGBA8 PNG encoder. It writes no gamma, sRGB or ICC chunks so pixel values stay exactly as given.
public enum PNGWriter {
    public static func encode(width: Int, height: Int, rgba: [UInt8], compress: Bool = true) throws -> Data {
        guard width > 0, height > 0, width <= 65535, height <= 65535,
              rgba.count == width * height * 4 else { throw PNGWriterError.invalidDimensions }
        var raw = [UInt8]()
        raw.reserveCapacity((width * 4 + 1) * height)
        for y in 0..<height {
            raw.append(0) // filter: none
            raw.append(contentsOf: rgba[(y * width * 4)..<((y + 1) * width * 4)])
        }
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        var ihdr = [UInt8]()
        ihdr += be32(width) + be32(height) + [8, 6, 0, 0, 0]
        png.append(chunk("IHDR", ihdr))
        png.append(chunk("IDAT", zlibStream(raw, compress: compress)))
        png.append(chunk("IEND", []))
        return png
    }

    static func chunk(_ type: String, _ body: [UInt8]) -> Data {
        let typeBytes = Array(type.utf8)
        var out = Data(be32(body.count))
        out.append(contentsOf: typeBytes)
        out.append(contentsOf: body)
        out.append(contentsOf: be32(Int(crc32(typeBytes + body))))
        return out
    }

    static func be32(_ v: Int) -> [UInt8] {
        [UInt8(truncatingIfNeeded: v >> 24), UInt8(truncatingIfNeeded: v >> 16),
         UInt8(truncatingIfNeeded: v >> 8), UInt8(truncatingIfNeeded: v)]
    }

    private static let crcTable: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in bytes { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }

    public static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for x in bytes {
            a = (a + UInt32(x)) % 65521
            b = (b + a) % 65521
        }
        return b << 16 | a
    }

    /// zlib stream: header + deflate data + Adler-32. Falls back to stored blocks if compression is unavailable.
    static func zlibStream(_ raw: [UInt8], compress: Bool) -> [UInt8] {
        var deflated: [UInt8]?
        if compress, !raw.isEmpty {
            var dst = [UInt8](repeating: 0, count: raw.count + raw.count / 8 + 1024)
            let n = compression_encode_buffer(&dst, dst.count, raw, raw.count, nil, COMPRESSION_ZLIB)
            if n > 0 { deflated = Array(dst[0..<n]) }
        }
        let body = deflated ?? storedBlocks(raw)
        return [0x78, deflated == nil ? 0x01 : 0x9C] + body + be32(Int(adler32(raw)))
    }

    static func storedBlocks(_ raw: [UInt8]) -> [UInt8] {
        var out = [UInt8]()
        var i = 0
        repeat {
            let len = min(65535, raw.count - i)
            let final: UInt8 = i + len >= raw.count ? 1 : 0
            out += [final, UInt8(len & 0xFF), UInt8(len >> 8), UInt8(~len & 0xFF), UInt8((~len >> 8) & 0xFF)]
            out += raw[i..<(i + len)]
            i += len
        } while i < raw.count
        return out
    }
}
