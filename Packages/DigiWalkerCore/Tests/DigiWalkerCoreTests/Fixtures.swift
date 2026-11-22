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
