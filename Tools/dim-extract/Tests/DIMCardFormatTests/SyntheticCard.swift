import DigiWalkerCore
import Foundation
@testable import DIMCardFormat

/// Builds a synthetic card image (no third-party data): 4 MiB buffer, tables, patterned sprites, then bitwise NOT.
struct SyntheticCard {
    var shuffleOffsets = false
    var terminator = true
    /// Overrides the stage written for a slot (to provoke a mismatch).
    var stageOverride: [Int: Int] = [:]
    var extraSprite = false
    /// Overrides (width, height) of a given sprite index.
    var sizeOverride: [Int: (Int, Int)] = [:]
    var spriteCountField: Int?
    var dimIdOverride: Int?
    /// Replaces the pointer-table offset of a sprite after layout.
    var offsetOverride: [Int: Int] = [:]

    static func pixel(sprite: Int, x: Int, y: Int) -> UInt16 {
        let v = UInt16(truncatingIfNeeded: sprite * 997 + x * 31 + y * 7 + 1)
        return v == RGB565.defaultTransparentKey ? 0x1234 : v
    }

    func build(card: EvolutionCard) -> Data {
        var sizes: [(Int, Int)] = [(4, 4), (6, 6)] + Array(repeating: (3, 3), count: 8)
        var slotFirstFrame: [Int: Int] = [:]
        let slots = card.stages.enumerated().flatMap { s, l in l.map { (s, $0) } }.sorted { $0.1.dimIndex < $1.1.dimIndex }
        var stages = [Int](repeating: 0, count: slots.count)
        for (stage, slot) in slots {
            let spec = SpeciesCatalog.info(id: slot.speciesId)!.dimSprite!
            stages[slot.dimIndex] = stage
            sizes.append((5, 2)) // name
            slotFirstFrame[slot.dimIndex] = sizes.count
            sizes += Array(repeating: (spec.frameWidth, spec.frameHeight), count: spec.frameCount)
            if stage >= 1 { sizes.append((4, 4)) } // full image
        }
        if extraSprite { sizes.append((2, 2)) }
        for (i, s) in sizeOverride { sizes[i] = s }

        var d = [UInt8](repeating: 0, count: DIMCardImage.imageSize)
        func put16(_ o: Int, _ v: Int) { d[o] = UInt8(v & 0xFF); d[o + 1] = UInt8((v >> 8) & 0xFF) }
        func put32(_ o: Int, _ v: Int) { put16(o, v & 0xFFFF); put16(o + 2, v >> 16) }
        put16(0x32, dimIdOverride ?? card.dimId)
        for (i, s) in stages.enumerated() {
            put16(DIMCardImage.statsOffset + i * DIMCardImage.statsEntrySize, stageOverride[i] ?? s)
        }
        let n = sizes.count
        put32(DIMCardImage.pointerTableOffset, 1)
        put32(DIMCardImage.pointerTableOffset + 4, 72)
        put32(DIMCardImage.pointerTableOffset + 8, spriteCountField ?? n)
        var cursor = 0x40 + 4 * (3 + n + 1)
        var offsets = [Int](repeating: 0, count: n)
        let order = shuffleOffsets ? Array((0..<n).reversed()) : Array(0..<n)
        for i in order {
            offsets[i] = cursor
            let (w, h) = sizes[i]
            for y in 0..<h { for x in 0..<w {
                put16(DIMCardImage.spriteAreaOffset + cursor + 2 * (y * w + x), Int(Self.pixel(sprite: i, x: x, y: y)))
            } }
            cursor += w * h * 2 + (i % 5 == 0 ? 2 : 0) // occasional padding like a re-saved card
        }
        for (i, o) in offsetOverride { offsets[i] = o }
        for i in 0..<n {
            put32(DIMCardImage.pointerTableOffset + 4 * (3 + i), offsets[i])
            put16(DIMCardImage.sizeTableOffset + 4 * i, sizes[i].0)
            put16(DIMCardImage.sizeTableOffset + 4 * i + 2, sizes[i].1)
        }
        put32(DIMCardImage.pointerTableOffset + 4 * (3 + n), cursor)
        if terminator {
            d[DIMCardImage.spriteAreaOffset + cursor] = 0x02
            for k in 1...3 { d[DIMCardImage.spriteAreaOffset + cursor + k] = 0xFF }
        }
        return Data(d.map { ~$0 })
    }
}
