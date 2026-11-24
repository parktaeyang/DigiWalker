import Foundation

public enum RGB565 {
    /// Pure green, the transparency key used by the cards checked so far (see local-notes plan, step 1 result).
    public static let defaultTransparentKey: UInt16 = 0x07E0

    /// Bit-replicating expansion to 8 bits per channel (0 stays 0, max stays 255). Alpha is 255.
    public static func rgba(_ value: UInt16) -> [UInt8] {
        let r5 = UInt8((value >> 11) & 0x1F), g6 = UInt8((value >> 5) & 0x3F), b5 = UInt8(value & 0x1F)
        return [r5 << 3 | r5 >> 2, g6 << 2 | g6 >> 4, b5 << 3 | b5 >> 2, 255]
    }
}
