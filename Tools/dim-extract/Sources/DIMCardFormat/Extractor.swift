import CryptoKit
import DigiWalkerCore
import Foundation

public struct ExtractOptions: Sendable {
    public var binURL: URL
    public var card: String
    public var outDirectory: URL
    public var dryRun = false
    public var force = false
    public var allowHashMismatch = false
    public var transparentKey = RGB565.defaultTransparentKey
    public var only: String?
    /// Repository root used to locate `PrivateAssets/`. Found by walking up from the working directory if nil.
    public var repoRoot: URL?
    public var allowOutsidePrivateAssets = false

    public init(binURL: URL, card: String, outDirectory: URL) {
        self.binURL = binURL
        self.card = card
        self.outDirectory = outDirectory
    }
}

public enum ExtractError: Error, Equatable, CustomStringConvertible {
    case hashMismatch(actual: String, expected: String)
    case dimIdMismatch(actual: Int, expected: Int, card: String)
    case notRegularFile(String)
    case repoRootNotFound
    case outsidePrivateAssets(String)
    case badRepoRoot(String)
    case privateAssetsIsLink
    case outputNotDirectory(String)

    public var description: String {
        switch self {
        case .hashMismatch(let a, let e):
            return "BIN SHA-256 prefix \(a) differs from the catalog id \(e); use --allow-hash-mismatch only after checking the file"
        case .dimIdMismatch(let a, let e, let c):
            return "BIN header dimId \(a) is not \(e), the dimId of card \(c); wrong --card or wrong file"
        case .notRegularFile(let n): return "\(n) exists and is not a regular file; refusing to replace it"
        case .repoRootNotFound:
            return "repository root not found (looked for Tools/dim-extract/Package.swift); pass --repo-root or --allow-outside-private-assets"
        case .badRepoRoot(let p): return "\(p) is not the repository root (Tools/dim-extract/Package.swift not found)"
        case .privateAssetsIsLink: return "<repo>/PrivateAssets is a symbolic link or resolves outside the repository; refusing to write through it"
        case .outputNotDirectory(let p): return "output location \(p) is not a directory"
        case .outsidePrivateAssets(let p):
            return "output \(p) resolves outside <repo>/PrivateAssets; use --allow-outside-private-assets only if intended"
        }
    }
}

public enum SheetOutcome: Equatable, Sendable {
    case wrote, wouldWrite, skippedExisting, skippedShared(baseCard: String)
}

public struct SheetResult: Sendable {
    public let speciesId: String
    public let dimIndex: Int
    public let frameSize: String
    public let frameCount: Int
    public let output: String
    public let outcome: SheetOutcome
}

public struct ExtractReport: Sendable {
    public let card: String
    public let shaPrefix: String
    public let hashMatches: Bool
    public let results: [SheetResult]
    public let warnings: [String]
}

public enum Extractor {
    public static func run(_ options: ExtractOptions) throws -> ExtractReport {
        let card = try SheetPlanner.resolveCard(options.card)
        let raw = try readBounded(options.binURL)
        let sha = SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined()
        let prefix = String(sha.prefix(16))
        let matches = prefix == card.catalogCardId
        var warnings: [String] = []
        if !matches {
            guard options.allowHashMismatch else {
                throw ExtractError.hashMismatch(actual: prefix, expected: card.catalogCardId)
            }
            warnings.append("SHA-256 prefix \(prefix) differs from catalog id \(card.catalogCardId); continuing by request")
        }
        try checkOutputLocation(options)

        let image = try DIMCardImage(raw: raw)
        // The dimId is checked even with --allow-hash-mismatch so a different card's BIN is never decoded as this one.
        guard image.headerDimId == card.dimId else {
            throw ExtractError.dimIdMismatch(actual: image.headerDimId, expected: card.dimId, card: card.id)
        }
        let sheets = try SheetPlanner.plan(card: card, image: image, only: options.only)

        // Encode everything first so a failure leaves no partial output.
        var encoded: [String: Data] = [:]
        for sheet in sheets where sheet.action == .write {
            let rgba = SheetPlanner.assemble(sheet, transparentKey: options.transparentKey)
            encoded[sheet.speciesId] = try PNGWriter.encode(width: sheet.sheetWidth, height: sheet.sheetHeight, rgba: rgba)
        }

        let fm = FileManager.default
        // Refuse directories, symlinks and other non-regular targets before writing anything (also with --force).
        for sheet in sheets where sheet.action == .write {
            let target = options.outDirectory.appendingPathComponent(sheet.fileName)
            if let attrs = try? fm.attributesOfItem(atPath: target.path), attrs[.type] as? FileAttributeType != .typeRegular {
                throw ExtractError.notRegularFile(sheet.fileName)
            }
        }
        var results: [SheetResult] = []
        for sheet in sheets {
            let target = options.outDirectory.appendingPathComponent(sheet.fileName)
            let outcome: SheetOutcome
            switch sheet.action {
            case .skipShared(let base): outcome = .skippedShared(baseCard: base)
            case .write:
                if fm.fileExists(atPath: target.path) && !options.force {
                    outcome = .skippedExisting
                } else if options.dryRun {
                    outcome = .wouldWrite
                } else {
                    try fm.createDirectory(at: options.outDirectory, withIntermediateDirectories: true)
                    let tmp = options.outDirectory.appendingPathComponent(".\(sheet.fileName).\(UUID().uuidString).tmp")
                    defer { try? fm.removeItem(at: tmp) }
                    try encoded[sheet.speciesId]!.write(to: tmp)
                    outcome = try commit(tmp: tmp, to: target, replace: options.force) ? .wrote : .skippedExisting
                }
            }
            results.append(SheetResult(speciesId: sheet.speciesId, dimIndex: sheet.dimIndex,
                                       frameSize: "\(sheet.spec.frameWidth)x\(sheet.spec.frameHeight)",
                                       frameCount: sheet.spec.frameCount,
                                       output: "\(sheet.sheetWidth)x\(sheet.sheetHeight)", outcome: outcome))
        }
        return ExtractReport(card: card.id, shaPrefix: prefix, hashMatches: matches, results: results, warnings: warnings)
    }

    /// Moves a finished temp file into place. Without `replace` the target is never overwritten: the temp file is
    /// hard-linked to it, which fails atomically with EEXIST if something appeared meanwhile (returns false).
    static func commit(tmp: URL, to target: URL, replace: Bool) throws -> Bool {
        if replace {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: tmp)
            return true
        }
        if link(tmp.path, target.path) == 0 { return true }
        if errno == EEXIST { return false }
        throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: target.path,
                                                      NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(errno))])
    }

    /// Reads at most `imageSize + 1` bytes so an oversized file is rejected before it is hashed.
    static func readBounded(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: DIMCardImage.imageSize + 1) ?? Data()
        guard data.count == DIMCardImage.imageSize else { throw DIMFormatError.wrongImageSize(data.count) }
        return data
    }

    public static func findRepoRoot(from start: URL) -> URL? {
        var dir = start.standardizedFileURL
        while true {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Tools/dim-extract/Package.swift").path) {
                return dir
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { return nil }
            dir = parent
        }
    }

    /// Resolves symlinks of the deepest existing ancestor and re-appends the missing components.
    static func resolved(_ url: URL) -> URL {
        var existing = url.standardizedFileURL
        var rest: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path),
              (try? FileManager.default.destinationOfSymbolicLink(atPath: existing.path)) == nil {
            rest.insert(existing.lastPathComponent, at: 0)
            let parent = existing.deletingLastPathComponent()
            if parent.path == existing.path { break }
            existing = parent
        }
        var out = existing.resolvingSymlinksInPath()
        for part in rest { out.appendPathComponent(part) }
        return out
    }

    static func isSymbolicLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    static func checkOutputLocation(_ options: ExtractOptions) throws {
        let out = resolved(options.outDirectory)
        // The nearest existing ancestor must be a directory (also for dry runs).
        var probe = out
        var isDir: ObjCBool = false
        while !FileManager.default.fileExists(atPath: probe.path, isDirectory: &isDir) {
            let parent = probe.deletingLastPathComponent()
            if parent.path == probe.path { break }
            probe = parent
        }
        guard isDir.boolValue else { throw ExtractError.outputNotDirectory(probe.path) }
        guard !options.allowOutsidePrivateAssets else { return }

        let rawRoot: URL
        if let given = options.repoRoot {
            guard FileManager.default.fileExists(atPath: given.appendingPathComponent("Tools/dim-extract/Package.swift").path) else {
                throw ExtractError.badRepoRoot(given.path)
            }
            rawRoot = given
        } else if let found = findRepoRoot(from: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) {
            rawRoot = found
        } else {
            throw ExtractError.repoRootNotFound
        }
        let root = rawRoot.standardizedFileURL.resolvingSymlinksInPath()
        let assets = root.appendingPathComponent("PrivateAssets")
        // PrivateAssets itself must be a real directory inside the repository, not a link to somewhere else.
        guard !isSymbolicLink(assets), resolved(assets).path == assets.path else { throw ExtractError.privateAssetsIsLink }
        guard out.path == assets.path || out.path.hasPrefix(assets.path + "/") else {
            throw ExtractError.outsidePrivateAssets(out.path)
        }
    }
}
