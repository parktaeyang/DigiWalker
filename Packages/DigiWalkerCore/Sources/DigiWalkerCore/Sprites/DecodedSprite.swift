import Foundation

/// 같은 행에서 같은 색이 이어지는 가로 구간. 투명 픽셀은 포함하지 않는다.
public struct PixelRun: Sendable, Hashable {
    public var y: Int
    public var x: Int
    public var length: Int
    public var color: RGBA8

    public init(y: Int, x: Int, length: Int, color: RGBA8) {
        self.y = y
        self.x = x
        self.length = length
        self.color = color
    }
}

public struct DecodedFrame: Sendable, Equatable {
    public let size: Int
    /// 행 우선 픽셀 색 배열 (size * size).
    public let pixels: [RGBA8]
    public let runs: [PixelRun]

    public init(size: Int, pixels: [RGBA8]) {
        self.size = size
        self.pixels = pixels
        self.runs = Self.makeRuns(size: size, pixels: pixels)
    }

    static func makeRuns(size: Int, pixels: [RGBA8]) -> [PixelRun] {
        var runs: [PixelRun] = []
        for y in 0..<size {
            var x = 0
            while x < size {
                let color = pixels[y * size + x]
                if color.isTransparent { x += 1; continue }
                var end = x + 1
                while end < size, pixels[y * size + end] == color { end += 1 }
                runs.append(PixelRun(y: y, x: x, length: end - x, color: color))
                x = end
            }
        }
        return runs
    }
}

public struct DecodedAnimation: Sendable, Equatable {
    public let frameDuration: Double
    public let frames: [DecodedFrame]
}

public struct DecodedSpecies: Sendable, Equatable {
    public let speciesId: String
    public let displayName: String
    public let stage: String
    public let evolvesTo: String?
    public let evolveAtLevel: Int?
    public let size: Int
    public let animations: [String: DecodedAnimation]

    public var idle: DecodedAnimation? { animations["idle"] }
}

/// 팩을 로드할 때 한 번 미리 계산한 불변 결과.
public struct SpriteLibrary: Sendable, Equatable {
    public let packId: String
    public let starterSpeciesId: String
    /// 팩에 정의된 순서.
    public let species: [DecodedSpecies]

    public func species(id: String) -> DecodedSpecies? {
        species.first { $0.speciesId == id }
    }

    public var starter: DecodedSpecies? { species(id: starterSpeciesId) }

    /// 검증을 통과한 팩만 넘겨야 한다. 검증 실패 시 `SpritePackError.invalid`를 던진다.
    public init(pack: SpritePack) throws {
        let issues = pack.validate()
        guard issues.isEmpty else { throw SpritePackError.invalid(issues) }
        self.packId = pack.packId
        self.starterSpeciesId = pack.starterSpeciesId
        self.species = pack.species.map(Self.decode)
    }

    private static func decode(_ sheet: SpriteSheet) -> DecodedSpecies {
        let colors = sheet.palette.reduce(into: [Character: RGBA8]()) { dict, entry in
            if let ch = entry.key.first, let color = RGBA8(hex: entry.value) { dict[ch] = color }
        }
        let animations = sheet.animations.mapValues { animation in
            DecodedAnimation(
                frameDuration: animation.frameDuration,
                frames: animation.frames.map { rows in
                    DecodedFrame(size: sheet.size, pixels: rows.flatMap { $0.map { colors[$0]! } })
                }
            )
        }
        return DecodedSpecies(
            speciesId: sheet.speciesId, displayName: sheet.displayName, stage: sheet.stage,
            evolvesTo: sheet.evolvesTo, evolveAtLevel: sheet.evolveAtLevel,
            size: sheet.size, animations: animations
        )
    }
}

/// 경과 시간으로 프레임 인덱스를 고른다. `paused`면 항상 0.
public func frameIndex(at date: Date, frameDuration: Double, frameCount: Int, paused: Bool = false) -> Int {
    guard !paused, frameCount > 1, frameDuration.isFinite, frameDuration > 0 else { return 0 }
    let raw = (date.timeIntervalSinceReferenceDate / frameDuration).rounded(.down)
    guard raw.isFinite else { return 0 }
    // arm64_32(Int 32비트)에서도 트랩하지 않도록 Double 상태에서 나머지를 먼저 구한다.
    let count = Double(frameCount)
    var m = raw.truncatingRemainder(dividingBy: count)
    if m < 0 { m += count }
    return min(max(Int(m), 0), frameCount - 1)
}

/// 가용 영역에 들어가는 가장 큰 정수 포인트 배율 (최대 `maxScale`, 최소 1).
public func integerPixelScale(spriteSize: Int, availableWidth: Double, availableHeight: Double, maxScale: Int = 4) -> Int {
    guard spriteSize > 0, availableWidth.isFinite, availableHeight.isFinite else { return 1 }
    let side = min(availableWidth, availableHeight)
    guard side >= Double(spriteSize) else { return 1 }
    let fit = Int(min(side / Double(spriteSize), Double(maxScale)).rounded(.down))
    return max(1, min(fit, maxScale))
}
