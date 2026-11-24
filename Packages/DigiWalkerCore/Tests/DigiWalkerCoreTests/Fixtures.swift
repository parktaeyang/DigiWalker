import Foundation
@testable import DigiWalkerCore

enum Fixtures {
    static let rows4A = ["a.b.", "aabb", "....", "bbbb"]
    static let rows4B = ["....", "a.b.", "aabb", "bbbb"]

    static func sheet(
        id: String = "s1", evolvesTo: String? = "s2", level: Int? = 5, size: Int = 4,
        palette: [String: String] = [".": "#00000000", "a": "#FF0000", "b": "#00FF0080"],
        animations: [String: SpriteAnimation]? = nil
    ) -> SpriteSheet {
        SpriteSheet(
            speciesId: id, displayName: id, stage: "baby", evolvesTo: evolvesTo, evolveAtLevel: level,
            size: size, palette: palette,
            animations: animations ?? [
                "idle": SpriteAnimation(frameDuration: 0.4, frames: [rows4A, rows4B]),
                "happy": SpriteAnimation(frameDuration: 0.25, frames: []),
            ]
        )
    }

    static func pack(_ species: [SpriteSheet]? = nil, starter: String = "s1") -> SpritePack {
        SpritePack(
            packId: "fixture",
            species: species ?? [sheet(), sheet(id: "s2", evolvesTo: nil, level: nil)],
            starterSpeciesId: starter
        )
    }

    static func write(_ pack: SpritePack, to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(pack).write(to: dir.appendingPathComponent("pack.json"))
    }

    static func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("dwcore-\(UUID().uuidString)")
    }
}

/// Deterministic SplitMix64 for reproducible random evolution.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Wraps a seeded generator and counts how many values were drawn.
struct CountingGenerator: RandomNumberGenerator {
    private var base: SeededGenerator
    private(set) var draws = 0
    init(seed: UInt64) { base = SeededGenerator(seed: seed) }
    mutating func next() -> UInt64 {
        draws += 1
        return base.next()
    }
}
