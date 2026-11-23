import Foundation

public struct StateFile<Value: Codable>: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() throws -> Value? {
        do {
            return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    public func save(_ value: Value) throws {
        let data = try JSONEncoder().encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
