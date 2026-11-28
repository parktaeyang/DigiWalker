import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// QR image for a battle payload. One pixel per module, so it can be drawn at a whole-number scale.
enum BattleQRImage {
    private static let context = CIContext(options: [.useSoftwareRenderer: true])
    private static let cache = NSCache<NSString, CGImage>()

    /// Cached by payload; the same QR is drawn on every redraw of the screen.
    static func make(_ payload: String) -> CGImage? {
        if let cached = cache.object(forKey: payload as NSString) { return cached }
        guard let image = render(payload) else { return nil }
        cache.setObject(image, forKey: payload as NSString)
        return image
    }

    private static func render(_ payload: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage else { return nil }
        return context.createCGImage(image, from: image.extent)
    }

    /// Whole-number scale that keeps `modules` modules within `side` points (at least 1).
    static func scale(modules: Int, side: CGFloat) -> Int {
        max(1, Int((side / CGFloat(max(1, modules))).rounded(.down)))
    }
}
