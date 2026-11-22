import Foundation

public struct SpriteAnimation: Sendable, Codable, Equatable {
    public var frameDuration: Double
    public var frames: [[String]]

    public init(frameDuration: Double, frames: [[String]]) {
        self.frameDuration = frameDuration
        self.frames = frames
    }
}

public struct SpriteSheet: Sendable, Codable, Equatable {
    public var speciesId: String
    public var displayName: String
    public var stage: String
    public var evolvesTo: String?
    public var evolveAtLevel: Int?
    public var size: Int
    public var palette: [String: String]
    public var animations: [String: SpriteAnimation]

    public init(
        speciesId: String, displayName: String, stage: String,
        evolvesTo: String? = nil, evolveAtLevel: Int? = nil,
        size: Int, palette: [String: String], animations: [String: SpriteAnimation]
    ) {
        self.speciesId = speciesId
        self.displayName = displayName
        self.stage = stage
        self.evolvesTo = evolvesTo
        self.evolveAtLevel = evolveAtLevel
        self.size = size
        self.palette = palette
        self.animations = animations
    }
}
