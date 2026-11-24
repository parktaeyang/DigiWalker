import Testing
@testable import DigiWalkerCore

@Suite struct SheetSlicingTests {
    private let small = DIMSpriteSpec(frameWidth: 32, frameHeight: 24, frameCount: 5)
    private let large = DIMSpriteSpec(frameWidth: 64, frameHeight: 56, frameCount: 12)

    @Test func horizontalStrip() throws {
        let frames = try SheetSlicing.frames(imageWidth: 160, imageHeight: 24, spec: small)
        #expect(frames.count == 5)
        #expect(frames[0] == SheetFrameRect(x: 0, y: 0, width: 32, height: 24))
        #expect(frames[4] == SheetFrameRect(x: 128, y: 0, width: 32, height: 24))
    }

    @Test func wideStripOfLargeFrames() throws {
        let frames = try SheetSlicing.frames(imageWidth: 768, imageHeight: 56, spec: large)
        #expect(frames.count == 12)
        #expect(frames[11] == SheetFrameRect(x: 704, y: 0, width: 64, height: 56))
    }

    @Test func verticalStrip() throws {
        let frames = try SheetSlicing.frames(imageWidth: 64, imageHeight: 672, spec: large)
        #expect(frames.count == 12)
        #expect(frames[1] == SheetFrameRect(x: 0, y: 56, width: 64, height: 56))
        #expect(frames[11] == SheetFrameRect(x: 0, y: 616, width: 64, height: 56))
    }

    @Test func gridIsRowMajor() throws {
        let frames = try SheetSlicing.frames(imageWidth: 256, imageHeight: 168, spec: large)
        #expect(frames.count == 12)
        #expect(frames[3] == SheetFrameRect(x: 192, y: 0, width: 64, height: 56))
        #expect(frames[4] == SheetFrameRect(x: 0, y: 56, width: 64, height: 56))
        #expect(frames[11] == SheetFrameRect(x: 192, y: 112, width: 64, height: 56))
    }

    @Test func extraCellsAreIgnored() throws {
        let frames = try SheetSlicing.frames(imageWidth: 192, imageHeight: 24, spec: small)
        #expect(frames.count == 5)
        #expect(frames.last == SheetFrameRect(x: 128, y: 0, width: 32, height: 24))
    }

    @Test func notEnoughCellsFails() {
        #expect(throws: SheetSlicingError.invalidSheet) {
            try SheetSlicing.frames(imageWidth: 192, imageHeight: 112, spec: large)
        }
    }

    @Test func nonDivisibleSizeFails() {
        #expect(throws: SheetSlicingError.invalidSheet) {
            try SheetSlicing.frames(imageWidth: 770, imageHeight: 56, spec: large)
        }
        #expect(throws: SheetSlicingError.invalidSheet) {
            try SheetSlicing.frames(imageWidth: 768, imageHeight: 57, spec: large)
        }
    }

    @Test func hugeSheetDoesNotOverflowCapacityCheck() throws {
        // Int32.max x Int32.max cells: a naive columns * rows product overflows a 32-bit Int.
        let spec = DIMSpriteSpec(frameWidth: 1, frameHeight: 1, frameCount: 3)
        let side = Int(Int32.max)
        let frames = try SheetSlicing.frames(imageWidth: side, imageHeight: side, spec: spec)
        #expect(frames.count == 3)
        #expect(frames[2] == SheetFrameRect(x: 2, y: 0, width: 1, height: 1))
        #expect(throws: SheetSlicingError.invalidSheet) {
            try SheetSlicing.frames(imageWidth: 2, imageHeight: 1, spec: spec)
        }
    }

    @Test func degenerateInputsFail() {
        #expect(throws: SheetSlicingError.invalidSheet) {
            try SheetSlicing.frames(imageWidth: 0, imageHeight: 0, spec: small)
        }
        #expect(throws: SheetSlicingError.invalidSheet) {
            try SheetSlicing.frames(imageWidth: 32, imageHeight: 24,
                                    spec: DIMSpriteSpec(frameWidth: 0, frameHeight: 24, frameCount: 1))
        }
    }

    @Test func catalogSpecsSliceAsDocumented() throws {
        for info in SpeciesCatalog.all {
            guard let spec = info.dimSprite else { continue }
            let frames = try SheetSlicing.frames(imageWidth: spec.frameWidth * spec.frameCount,
                                                 imageHeight: spec.frameHeight, spec: spec)
            #expect(frames.count == spec.frameCount)
        }
    }
}
