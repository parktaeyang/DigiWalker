import DigiWalkerCore
import Foundation

public enum PlanError: Error, Equatable, CustomStringConvertible {
    case unknownCard(String)
    case missingSpec(speciesId: String)
    case stageMismatch(speciesId: String, bin: Int, core: Int)
    case spriteCountMismatch(bin: Int, expected: Int)
    case frameSizeMismatch(speciesId: String, frame: Int, width: Int, height: Int)
    case sheetRejected(speciesId: String)
    case unknownSpecies(String)

    public var description: String {
        switch self {
        case .unknownCard(let c): return "unknown card '\(c)'"
        case .missingSpec(let s): return "\(s): no DIM sprite spec in the core catalog"
        case .stageMismatch(let s, let b, let c): return "\(s): BIN stage \(b) differs from core stage \(c)"
        case .spriteCountMismatch(let b, let e): return "BIN has \(b) sprites, core card layout expects \(e)"
        case .frameSizeMismatch(let s, let f, let w, let h): return "\(s): frame \(f) is \(w)x\(h), not the core spec"
        case .sheetRejected(let s): return "\(s): output sheet is rejected by SheetSlicing"
        case .unknownSpecies(let s): return "--only: '\(s)' is not a slot of this card"
        }
    }
}

public enum PlannedAction: Equatable, Sendable {
    case write
    /// Shared species written from another (base) card only.
    case skipShared(baseCard: String)
}

public struct PlannedSheet: Sendable {
    public let speciesId: String
    public let dimIndex: Int
    public let spec: DIMSpriteSpec
    public let action: PlannedAction
    public let sheetWidth: Int
    public let sheetHeight: Int
    public let frames: [DIMSprite]
    public var fileName: String { speciesId + ".png" }
}

public enum SheetPlanner {
    /// Sprites that belong to one slot: name, `frameCount` frames, and a full image from stage 1 up.
    static func spritesPerSlot(stage: Int, spec: DIMSpriteSpec) -> Int {
        1 + spec.frameCount + (stage >= 1 ? 1 : 0)
    }

    /// First card in `SpeciesCatalog.cards` that lists the species. Shared species are written from that card only.
    public static func baseCard(of speciesId: String) -> EvolutionCard? {
        SpeciesCatalog.cards.first { $0.slot(of: speciesId) != nil }
    }

    public static func resolveCard(_ key: String) throws -> EvolutionCard {
        if let c = SpeciesCatalog.cards.first(where: { $0.id == key || $0.catalogCardId == key }) { return c }
        throw PlanError.unknownCard(key)
    }

    /// Validates the whole card against the core layout; throws before anything is written.
    public static func plan(card: EvolutionCard, image: DIMCardImage, only: String? = nil) throws -> [PlannedSheet] {
        let slots = card.stages.enumerated().flatMap { stage, list in list.map { (stage, $0) } }
            .sorted { $0.1.dimIndex < $1.1.dimIndex }
        if let only, !slots.contains(where: { $0.1.speciesId == only }) { throw PlanError.unknownSpecies(only) }

        var specs: [DIMSpriteSpec] = []
        for (stage, slot) in slots {
            guard let spec = SpeciesCatalog.info(id: slot.speciesId)?.dimSprite else {
                throw PlanError.missingSpec(speciesId: slot.speciesId)
            }
            specs.append(spec)
            _ = stage
        }
        let expected = DIMCardImage.leadingSpriteCount
            + zip(slots, specs).reduce(0) { $0 + spritesPerSlot(stage: $1.0.0, spec: $1.1) }
        guard image.spriteCount == expected else {
            throw PlanError.spriteCountMismatch(bin: image.spriteCount, expected: expected)
        }

        var cursor = DIMCardImage.leadingSpriteCount
        var sheets: [PlannedSheet] = []
        for ((stage, slot), spec) in zip(slots, specs) {
            let binStage = try image.stage(ofSlot: slot.dimIndex)
            guard binStage == stage else {
                throw PlanError.stageMismatch(speciesId: slot.speciesId, bin: binStage, core: stage)
            }
            let firstFrame = cursor + 1
            cursor += spritesPerSlot(stage: stage, spec: spec)
            // Sizes are checked for every slot, written or not, so a layout drift cannot hide behind a skipped slot.
            for k in 0..<spec.frameCount {
                let s = try image.spriteSize(at: firstFrame + k)
                guard s.width == spec.frameWidth, s.height == spec.frameHeight else {
                    throw PlanError.frameSizeMismatch(speciesId: slot.speciesId, frame: k, width: s.width, height: s.height)
                }
            }
            let base = baseCard(of: slot.speciesId)
            let action: PlannedAction = (base?.id == card.id) ? .write : .skipShared(baseCard: base?.id ?? "?")
            if let only, only != slot.speciesId { continue }
            let width = spec.frameWidth * spec.frameCount, height = spec.frameHeight
            guard let rects = try? SheetSlicing.frames(imageWidth: width, imageHeight: height, spec: spec),
                  rects.count == spec.frameCount else { throw PlanError.sheetRejected(speciesId: slot.speciesId) }
            let frames = action == .write ? try (0..<spec.frameCount).map { try image.sprite(at: firstFrame + $0) } : []
            sheets.append(PlannedSheet(speciesId: slot.speciesId, dimIndex: slot.dimIndex, spec: spec, action: action,
                                       sheetWidth: width, sheetHeight: height, frames: frames))
        }
        return sheets
    }

    /// Lays frames out in one row and converts RGB565 to RGBA8 (key colour becomes alpha 0, everything else alpha 255).
    public static func assemble(_ sheet: PlannedSheet, transparentKey: UInt16) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: sheet.sheetWidth * sheet.sheetHeight * 4)
        for (k, frame) in sheet.frames.enumerated() {
            for y in 0..<frame.height {
                for x in 0..<frame.width {
                    let v = frame.pixels[y * frame.width + x]
                    guard v != transparentKey else { continue }
                    let o = (y * sheet.sheetWidth + k * frame.width + x) * 4
                    out.replaceSubrange(o..<(o + 4), with: RGB565.rgba(v))
                }
            }
        }
        return out
    }
}
