import Foundation

public struct SheetFrameRect: Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int
}

public enum SheetSlicingError: Error, Equatable, Sendable {
    case invalidSheet
}

/// Splits a DIM sheet image into frame rectangles without touching pixels.
/// Frames run row-major (left to right, then top to bottom), so one row, one column and a grid share one formula.
public enum SheetSlicing {
    public static func frames(imageWidth: Int, imageHeight: Int,
                              spec: DIMSpriteSpec) throws -> [SheetFrameRect] {
        let fw = spec.frameWidth, fh = spec.frameHeight, count = spec.frameCount
        guard imageWidth > 0, imageHeight > 0, fw > 0, fh > 0, count > 0,
              imageWidth % fw == 0, imageHeight % fh == 0 else { throw SheetSlicingError.invalidSheet }
        let columns = imageWidth / fw
        let rows = imageHeight / fh
        // Capacity check without multiplying (columns * rows could overflow Int on 32-bit watches).
        guard (count - 1) / columns < rows else { throw SheetSlicingError.invalidSheet }
        return (0..<count).map { SheetFrameRect(x: ($0 % columns) * fw, y: ($0 / columns) * fh, width: fw, height: fh) }
    }
}
