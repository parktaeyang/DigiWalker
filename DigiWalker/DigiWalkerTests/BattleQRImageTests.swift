import AVFoundation
import CoreImage
import DigiWalkerCore
import Testing
@testable import DigiWalker

@MainActor
struct BattleQRImageTests {
    private func readBack(_ image: CGImage) -> String? {
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        // Detectors need some breathing room and bigger modules: scale up by whole numbers with a white border.
        let k = 8
        let side = (image.width + 8) * k
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 4 * k, y: 4 * k, width: image.width * k, height: image.height * k))
        guard let big = ctx.makeImage() else { return nil }
        let features = detector?.features(in: CIImage(cgImage: big)) ?? []
        return (features.first as? CIQRCodeFeature)?.messageString
    }

    @Test func imageIsSquareAndScalesByWholeNumbers() throws {
        let image = try #require(BattleQRImage.make(BattleCard(speciesId: "agumon", name: "아구몬")!.encoded()))
        #expect(image.width == image.height)
        #expect(BattleQRImage.scale(modules: image.width + 8, side: 220) >= 4)
        #expect(BattleQRImage.scale(modules: 1000, side: 220) == 1)
    }

    @Test func payloadsReadBackFromTheImage() throws {
        let longest = SpeciesCatalog.cardSpeciesIds.compactMap { id in
            SpeciesCatalog.info(id: id).flatMap { BattleCard(speciesId: id, name: $0.name) }
        }.max { $0.encoded().utf8.count < $1.encoded().utf8.count }!
        for card in [BattleCard(speciesId: "agumon", name: "아구몬")!, BattleCard(speciesId: "botamon", name: "깜몬")!, longest] {
            let payload = card.encoded()
            let image = try #require(BattleQRImage.make(payload))
            #expect(readBack(image) == payload, "\(card.speciesId)")
        }
    }

    @Test func sameQRImageIsReused() throws {
        let payload = BattleCard(speciesId: "agumon", name: "아구몬")!.encoded()
        let a = try #require(BattleQRImage.make(payload))
        let b = try #require(BattleQRImage.make(payload))
        #expect(a === b)
    }

    @Test func cameraAccessDecision() {
        #expect(BattleCameraAccess.decide(status: .authorized, supported: true, available: true) == .ready)
        #expect(BattleCameraAccess.decide(status: .authorized, supported: true, available: false) == .unavailable)
        #expect(BattleCameraAccess.decide(status: .authorized, supported: false, available: false) == .unsupported)
        #expect(BattleCameraAccess.decide(status: .denied, supported: true, available: false) == .denied)
        #expect(BattleCameraAccess.decide(status: .authorized, supported: false, available: true) == .unsupported)
        #expect(BattleCameraAccess.decide(status: .restricted, supported: true, available: false) == .denied)
        #expect(BattleCameraAccess.decide(status: .notDetermined, supported: true, available: false) == .checking)
        #expect(BattleCameraAccess.decide(status: .denied, supported: false, available: false) == .unsupported)
    }
}
