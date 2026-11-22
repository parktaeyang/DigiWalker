import Foundation

public struct SpritePack: Sendable, Codable, Equatable {
    public var packId: String
    public var species: [SpriteSheet]
    public var starterSpeciesId: String

    public init(packId: String, species: [SpriteSheet], starterSpeciesId: String) {
        self.packId = packId
        self.species = species
        self.starterSpeciesId = starterSpeciesId
    }
}
