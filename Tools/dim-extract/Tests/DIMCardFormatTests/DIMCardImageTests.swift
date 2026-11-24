import DigiWalkerCore
import Foundation
import Testing
@testable import DIMCardFormat

struct DIMCardImageTests {
    @Test func rgb565ExpandsByBitReplication() {
        #expect(RGB565.rgba(0x0000) == [0, 0, 0, 255])
        #expect(RGB565.rgba(0xFFFF) == [255, 255, 255, 255])
        #expect(RGB565.rgba(0xF800) == [255, 0, 0, 255])
        #expect(RGB565.rgba(0x07E0) == [0, 255, 0, 255])
        #expect(RGB565.rgba(0x0001) == [0, 0, 8, 255])
    }

    @Test func parsesSyntheticCardIncludingShuffledOffsets() throws {
        for shuffle in [false, true] {
            var synth = SyntheticCard()
            synth.shuffleOffsets = shuffle
            let image = try DIMCardImage(raw: synth.build(card: .agumonEX))
            #expect(image.spriteCount == 233)
            let s = try image.sprite(at: 30)
            #expect(s.pixels[0] == SyntheticCard.pixel(sprite: 30, x: 0, y: 0))
            #expect(s.pixels[s.width + 2] == SyntheticCard.pixel(sprite: 30, x: 2, y: 1))
            #expect(try image.stage(ofSlot: 2) == 2)
            #expect(try image.stage(ofSlot: 16) == 5)
        }
    }

    @Test func rejectsBrokenImages() throws {
        #expect(throws: DIMFormatError.wrongImageSize(10)) { try DIMCardImage(raw: Data(count: 10)) }
        #expect(throws: DIMFormatError.self) { try DIMCardImage(raw: Data(repeating: 0xFF, count: DIMCardImage.imageSize)) }
        var noTerm = SyntheticCard(); noTerm.terminator = false
        #expect(throws: DIMFormatError.badTerminator) { try DIMCardImage(raw: noTerm.build(card: .agumonEX)) }
        var many = SyntheticCard(); many.spriteCountField = 5000
        #expect(throws: DIMFormatError.self) { try DIMCardImage(raw: many.build(card: .agumonEX)) }
        var zero = SyntheticCard(); zero.sizeOverride = [12: (0, 4)]
        #expect(throws: DIMFormatError.self) { try DIMCardImage(raw: zero.build(card: .agumonEX)) }
        var huge = SyntheticCard(); huge.sizeOverride = [12: (257, 4)]
        #expect(throws: DIMFormatError.self) { try DIMCardImage(raw: huge.build(card: .agumonEX)) }
    }

    @Test func rejectsOutOfRangeAccess() throws {
        let image = try DIMCardImage(raw: SyntheticCard().build(card: .agumonEX))
        #expect(throws: DIMFormatError.spriteIndexOutOfRange(999)) { try image.sprite(at: 999) }
        #expect(throws: DIMFormatError.slotOutOfRange(-1)) { try image.stage(ofSlot: -1) }
    }

    @Test func rejectsOverlapOutOfRangeAndMissingTerminatorOrder() throws {
        let card = EvolutionCard.agumonEX
        let base = try DIMCardImage(raw: SyntheticCard().build(card: card))
        let first = 0x40 + 4 * (3 + base.spriteCount + 1)
        var overlap = SyntheticCard(); overlap.offsetOverride = [20: first + 2] // sprite 0 starts here
        #expect(throws: DIMFormatError.self) { try DIMCardImage(raw: overlap.build(card: card)) }
        var past = SyntheticCard(); past.offsetOverride = [20: DIMCardImage.imageSize - DIMCardImage.spriteAreaOffset - 4]
        #expect(throws: DIMFormatError.spriteOutOfRange(index: 20)) { try DIMCardImage(raw: past.build(card: card)) }
        var inTable = SyntheticCard(); inTable.offsetOverride = [20: 0x44]
        #expect(throws: DIMFormatError.spriteOutOfRange(index: 20)) { try DIMCardImage(raw: inTable.build(card: card)) }
    }

    @Test func terminatorMustLieAfterEverySprite() throws {
        let card = EvolutionCard.agumonEX
        let image = try DIMCardImage(raw: SyntheticCard().build(card: card))
        // Move the last sprite far past the terminator.
        var late = SyntheticCard(); late.offsetOverride = [image.spriteCount - 1: 0x2F0000]
        #expect(throws: DIMFormatError.badTerminator) { try DIMCardImage(raw: late.build(card: card)) }
    }

    @Test func spriteCountFieldMismatchFails() throws {
        var fewer = SyntheticCard(); fewer.spriteCountField = 232
        #expect(throws: (any Error).self) { try DIMCardImage(raw: fewer.build(card: .agumonEX)) }
    }
}
