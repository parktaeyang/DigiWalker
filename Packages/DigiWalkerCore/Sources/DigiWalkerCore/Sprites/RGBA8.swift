import Foundation

/// 8비트 RGBA 색. `#RRGGBB` 또는 `#RRGGBBAA` 문자열에서 만든다.
public struct RGBA8: Sendable, Hashable, Codable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// 알파가 0이면 투명 픽셀로 취급한다.
    public var isTransparent: Bool { a == 0 }

    public init?(hex: String) {
        guard hex.first == "#" else { return nil }
        let digits = hex.dropFirst()
        guard digits.count == 6 || digits.count == 8,
              digits.allSatisfy({ $0.isASCII && $0.isHexDigit }),
              let value = UInt32(digits, radix: 16)
        else { return nil }
        if digits.count == 6 {
            self.init(r: UInt8((value >> 16) & 0xFF), g: UInt8((value >> 8) & 0xFF), b: UInt8(value & 0xFF))
        } else {
            self.init(
                r: UInt8((value >> 24) & 0xFF), g: UInt8((value >> 16) & 0xFF),
                b: UInt8((value >> 8) & 0xFF), a: UInt8(value & 0xFF)
            )
        }
    }
}
