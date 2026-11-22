import Foundation

public enum SpritePackError: Error, Sendable, CustomStringConvertible {
    case fileNotFound(URL)
    case decoding(String)
    case invalid([SpriteValidationIssue])

    public var description: String {
        switch self {
        case .fileNotFound(let url): "pack.json 없음: \(url.path)"
        case .decoding(let reason): "JSON 디코딩 실패: \(reason)"
        case .invalid(let issues): "검증 실패 (\(issues.count)건): " + issues.prefix(5).map(\.description).joined(separator: "; ")
        }
    }
}

public enum SpritePackLoader {
    public static let fileName = "pack.json"

    /// 디렉토리 안의 `pack.json`을 읽어 검증하고 `SpriteLibrary`로 만든다.
    public static func load(directory: URL) throws -> SpriteLibrary {
        let file = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: file) else { throw SpritePackError.fileNotFound(file) }
        return try load(data: data)
    }

    public static func load(data: Data) throws -> SpriteLibrary {
        let pack: SpritePack
        do {
            pack = try JSONDecoder().decode(SpritePack.self, from: data)
        } catch {
            throw SpritePackError.decoding(String(describing: error))
        }
        return try SpriteLibrary(pack: pack)
    }
}

public struct SpritePackSkip: Sendable {
    public var directory: URL
    public var reason: String

    public init(directory: URL, reason: String) {
        self.directory = directory
        self.reason = reason
    }
}

public struct SpritePackResolution: Sendable {
    public var library: SpriteLibrary
    public var sourceDirectory: URL
    public var skipped: [SpritePackSkip]
}

public struct SpritePackResolutionFailure: Error, Sendable {
    public var skipped: [SpritePackSkip]

    public init(skipped: [SpritePackSkip]) { self.skipped = skipped }
}

public enum SpritePackResolver {
    /// 후보를 순서대로 시도해 처음 유효한 팩을 돌려준다. 건너뛴 후보와 이유를 함께 담는다.
    /// 후보 URL이 nil인 항목(번들에 폴더 없음)은 호출 측에서 제외하고 넘긴다.
    public static func resolve(candidates: [URL]) throws -> SpritePackResolution {
        var skipped: [SpritePackSkip] = []
        for directory in candidates {
            do {
                let library = try SpritePackLoader.load(directory: directory)
                return SpritePackResolution(library: library, sourceDirectory: directory, skipped: skipped)
            } catch {
                skipped.append(SpritePackSkip(directory: directory, reason: String(describing: error)))
            }
        }
        throw SpritePackResolutionFailure(skipped: skipped)
    }
}
