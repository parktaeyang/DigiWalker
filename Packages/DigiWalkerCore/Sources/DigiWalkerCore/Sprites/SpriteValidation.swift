import Foundation

public struct SpriteValidationIssue: Sendable, Equatable, CustomStringConvertible {
    public var speciesId: String?
    public var animation: String?
    public var frame: Int?
    public var row: Int?
    public var message: String

    public init(speciesId: String? = nil, animation: String? = nil, frame: Int? = nil, row: Int? = nil, message: String) {
        self.speciesId = speciesId
        self.animation = animation
        self.frame = frame
        self.row = row
        self.message = message
    }

    public var description: String {
        var parts: [String] = []
        if let speciesId { parts.append(speciesId) }
        if let animation { parts.append(animation) }
        if let frame { parts.append("frame \(frame)") }
        if let row { parts.append("row \(row)") }
        let location = parts.joined(separator: "/")
        return location.isEmpty ? message : "\(location): \(message)"
    }
}

extension SpriteSheet {
    public static let sizeRange = 1...64
    public static let frameDurationRange: ClosedRange<Double> = 0.05...10

    /// 이 종 하나에 대한 검증. 팩 단위 검증(중복, evolvesTo 참조)은 `SpritePack.validate()`가 한다.
    public func validate() -> [SpriteValidationIssue] {
        var issues: [SpriteValidationIssue] = []
        func add(_ message: String, animation: String? = nil, frame: Int? = nil, row: Int? = nil) {
            issues.append(.init(speciesId: speciesId, animation: animation, frame: frame, row: row, message: message))
        }

        if !Self.sizeRange.contains(size) {
            add("size \(size)는 \(Self.sizeRange.lowerBound)~\(Self.sizeRange.upperBound) 범위를 벗어났다")
        }

        for (key, value) in palette {
            if key.count != 1 { add("팔레트 키 \"\(key)\"는 한 글자여야 한다") }
            if RGBA8(hex: value) == nil { add("팔레트 \"\(key)\"의 색 \"\(value)\"를 해석할 수 없다") }
        }

        if (evolvesTo == nil) != (evolveAtLevel == nil) {
            add("evolvesTo와 evolveAtLevel은 둘 다 있거나 둘 다 없어야 한다")
        }
        if let level = evolveAtLevel, level < 2 {
            add("evolveAtLevel은 2 이상이어야 한다 (현재 \(level))")
        }
        if let evolvesTo, evolvesTo == speciesId {
            add("evolvesTo가 자기 자신이다")
        }

        if let idle = animations["idle"] {
            if idle.frames.isEmpty { add("idle 애니메이션에는 프레임이 1개 이상 필요하다", animation: "idle") }
        } else {
            add("idle 애니메이션이 없다")
        }

        for name in animations.keys.sorted() {
            guard let animation = animations[name] else { continue }
            if !Self.frameDurationRange.contains(animation.frameDuration) {
                add("frameDuration \(animation.frameDuration)은 \(Self.frameDurationRange.lowerBound)~\(Self.frameDurationRange.upperBound)초 범위를 벗어났다", animation: name)
            }
            for (f, rows) in animation.frames.enumerated() {
                if rows.count != size {
                    add("줄 수 \(rows.count) != size \(size)", animation: name, frame: f)
                }
                for (y, line) in rows.enumerated() {
                    if line.count != size {
                        add("줄 길이 \(line.count) != size \(size)", animation: name, frame: f, row: y)
                    }
                    for ch in line where palette[String(ch)] == nil {
                        add("팔레트에 없는 문자 \"\(ch)\"", animation: name, frame: f, row: y)
                        break
                    }
                }
            }
        }
        return issues
    }
}

extension SpritePack {
    public func validate() -> [SpriteValidationIssue] {
        var issues: [SpriteValidationIssue] = []
        var seen = Set<String>()
        for sheet in species {
            if !seen.insert(sheet.speciesId).inserted {
                issues.append(.init(speciesId: sheet.speciesId, message: "speciesId가 중복되었다"))
            }
        }
        for sheet in species {
            issues += sheet.validate()
            if let target = sheet.evolvesTo, target != sheet.speciesId, !seen.contains(target) {
                issues.append(.init(speciesId: sheet.speciesId, message: "evolvesTo \"\(target)\"가 팩 안에 없다"))
            }
        }
        let next = Dictionary(species.compactMap { s in s.evolvesTo.map { (s.speciesId, $0) } }, uniquingKeysWith: { a, _ in a })
        var reportedCycle = Set<String>()
        for sheet in species {
            var visited: [String] = [sheet.speciesId]
            var current = sheet.speciesId
            while let n = next[current] {
                if let at = visited.firstIndex(of: n) {
                    let cycle = Set(visited[at...])
                    if n != current, reportedCycle.isDisjoint(with: cycle) {
                        reportedCycle.formUnion(cycle)
                        issues.append(.init(speciesId: sheet.speciesId, message: "evolvesTo가 순환한다: " + (visited[at...] + [n]).joined(separator: " -> ")))
                    }
                    break
                }
                visited.append(n)
                current = n
            }
        }
        if !seen.contains(starterSpeciesId) {
            issues.append(.init(message: "starterSpeciesId \"\(starterSpeciesId)\"가 팩 안에 없다"))
        }
        return issues
    }
}
