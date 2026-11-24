import Foundation

public enum DIMFormatError: Error, Equatable, CustomStringConvertible {
    case wrongImageSize(Int)
    case badPointerTable(String)
    case spriteOutOfRange(index: Int)
    case spriteOverlap(index: Int)
    case badSpriteSize(index: Int, width: Int, height: Int)
    case badTerminator
    case slotOutOfRange(Int)
    case spriteIndexOutOfRange(Int)

    public var description: String {
        switch self {
        case .wrongImageSize(let n): return "BIN size is \(n) bytes, expected \(DIMCardImage.imageSize)"
        case .badPointerTable(let why): return "sprite pointer table is invalid: \(why)"
        case .spriteOutOfRange(let i): return "sprite \(i) lies outside the image"
        case .spriteOverlap(let i): return "sprite \(i) overlaps another sprite"
        case .badSpriteSize(let i, let w, let h): return "sprite \(i) has an invalid size \(w)x\(h)"
        case .badTerminator: return "sprite area terminator bytes were not found"
        case .slotOutOfRange(let s): return "slot \(s) is outside the stats table"
        case .spriteIndexOutOfRange(let i): return "sprite index \(i) does not exist"
        }
    }
}

/// One decoded sprite: little-endian R5G6B5 words, row-major.
public struct DIMSprite: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt16]

    public init(width: Int, height: Int, pixels: [UInt16]) {
        precondition(width > 0 && height > 0 && pixels.count == width * height)
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}

/// Read-only view of a 4 MiB DIM card image.
///
/// Layout facts (from the public "VB DIM Format" notes by cfogrady, cross-checked against local files):
/// - the whole image is bitwise NOT; words are little endian
/// - 0x30000 stats table, 24 bytes per slot, first word is the stage (0 = baby I ... 5 = ultimate)
/// - 0x60000 sprite size table, 4 bytes per sprite (width, height)
/// - 0x100000 sprite area; pointer table at 0x100040: [1, 72, spriteCount, offset * count, terminatorOffset];
///   offsets are relative to 0x100000 and point to width * height * 2 bytes of R5G6B5.
///   Offsets need not be ascending (a re-saved card can store sprites in another order).
/// - sprite order: logo, background, 8 eggs, then per slot: name, frames..., (full image for stage >= 1)
public struct DIMCardImage: Sendable {
    public static let imageSize = 4 * 1024 * 1024
    public static let statsOffset = 0x30000
    public static let statsEntrySize = 24
    public static let sizeTableOffset = 0x60000
    public static let sizeTableLimit = 0x70000
    public static let spriteAreaOffset = 0x100000
    public static let pointerTableOffset = 0x100040
    public static let leadingSpriteCount = 10
    public static let maxSpriteCount = 1024
    public static let maxSpriteSide = 256

    /// Bit-inverted copy of the file.
    private let bytes: [UInt8]
    public let spriteCount: Int
    private let offsets: [Int]
    private let sizes: [(width: Int, height: Int)]

    public init(raw: Data) throws {
        guard raw.count == Self.imageSize else { throw DIMFormatError.wrongImageSize(raw.count) }
        let inverted = raw.map { ~$0 }
        bytes = inverted

        func u16(_ o: Int) -> Int { Int(inverted[o]) | Int(inverted[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }

        let head = (u32(Self.pointerTableOffset), u32(Self.pointerTableOffset + 4))
        guard head == (1, 72) else { throw DIMFormatError.badPointerTable("unexpected header words") }
        let count = u32(Self.pointerTableOffset + 8)
        guard count > 0, count <= Self.maxSpriteCount else {
            throw DIMFormatError.badPointerTable("sprite count \(count) out of range")
        }
        guard Self.sizeTableOffset + 4 * count <= Self.sizeTableLimit else {
            throw DIMFormatError.badPointerTable("size table does not fit")
        }
        let tableEnd = Self.pointerTableOffset - Self.spriteAreaOffset + 4 * (3 + count + 1)
        var offs: [Int] = []
        var dims: [(width: Int, height: Int)] = []
        var spans: [(start: Int, end: Int, index: Int)] = []
        var maxEnd = 0
        for i in 0..<count {
            let off = u32(Self.pointerTableOffset + 4 * (3 + i))
            let w = u16(Self.sizeTableOffset + 4 * i)
            let h = u16(Self.sizeTableOffset + 4 * i + 2)
            guard (1...Self.maxSpriteSide).contains(w), (1...Self.maxSpriteSide).contains(h) else {
                throw DIMFormatError.badSpriteSize(index: i, width: w, height: h)
            }
            let end = off + w * h * 2
            guard off >= tableEnd, Self.spriteAreaOffset + end <= Self.imageSize else {
                throw DIMFormatError.spriteOutOfRange(index: i)
            }
            offs.append(off)
            dims.append((w, h))
            spans.append((off, end, i))
            maxEnd = max(maxEnd, end)
        }
        spans.sort { $0.start < $1.start }
        for (a, b) in zip(spans, spans.dropFirst()) where a.end > b.start {
            throw DIMFormatError.spriteOverlap(index: b.index)
        }
        let term = u32(Self.pointerTableOffset + 4 * (3 + count))
        guard term >= maxEnd, Self.spriteAreaOffset + term + 4 <= Self.imageSize,
              inverted[Self.spriteAreaOffset + term] == 0x02,
              inverted[Self.spriteAreaOffset + term + 1] == 0xFF,
              inverted[Self.spriteAreaOffset + term + 2] == 0xFF,
              inverted[Self.spriteAreaOffset + term + 3] == 0xFF else { throw DIMFormatError.badTerminator }
        spriteCount = count
        offsets = offs
        sizes = dims
    }

    /// Header word at 0x32 (DIM id, informational only).
    public var headerDimId: Int { Int(bytes[0x32]) | Int(bytes[0x33]) << 8 }

    public func stage(ofSlot slot: Int) throws -> Int {
        let o = Self.statsOffset + slot * Self.statsEntrySize
        guard slot >= 0, o + 2 <= Self.sizeTableOffset else { throw DIMFormatError.slotOutOfRange(slot) }
        return Int(bytes[o]) | Int(bytes[o + 1]) << 8
    }

    public func spriteSize(at index: Int) throws -> (width: Int, height: Int) {
        guard sizes.indices.contains(index) else { throw DIMFormatError.spriteIndexOutOfRange(index) }
        return sizes[index]
    }

    public func sprite(at index: Int) throws -> DIMSprite {
        guard sizes.indices.contains(index) else { throw DIMFormatError.spriteIndexOutOfRange(index) }
        let (w, h) = sizes[index]
        let base = Self.spriteAreaOffset + offsets[index]
        let pixels = (0..<(w * h)).map { UInt16(bytes[base + 2 * $0]) | UInt16(bytes[base + 2 * $0 + 1]) << 8 }
        return DIMSprite(width: w, height: h, pixels: pixels)
    }
}
