import DigiWalkerCore
import Foundation

public enum CommandLineError: Error, Equatable, CustomStringConvertible {
    case missingValue(String)
    case unknownArgument(String)
    case invalidValue(flag: String, value: String)
    case missingRequired

    public var description: String {
        switch self {
        case .missingValue(let f): return "\(f) needs a value (a token starting with -- is not a value)"
        case .unknownArgument(let a): return "unknown argument '\(a)'"
        case .invalidValue(let f, let v): return "invalid value '\(v)' for \(f)"
        case .missingRequired: return "--bin, --card and --out are required"
        }
    }
}

public enum CommandLineOptions {
    public static let usage = """
    usage: dim-extract --bin <file.bin> --card <\(SpeciesCatalog.cards.map(\.id).joined(separator: "|"))|catalog id> --out <dir>
                       [--dry-run] [--force] [--allow-hash-mismatch] [--transparent-key 0x07E0] [--only <speciesId>]
                       [--repo-root <dir>] [--allow-outside-private-assets]
    """

    /// Returns nil for --help.
    public static func parse(_ arguments: [String]) throws -> ExtractOptions? {
        var args = arguments
        var bin: String?, card: String?, out: String?, only: String?, root: String?
        var dryRun = false, force = false, allowMismatch = false, allowOutside = false
        var key = RGB565.defaultTransparentKey

        func value(_ flag: String) throws -> String {
            guard let v = args.first, !v.hasPrefix("--") else { throw CommandLineError.missingValue(flag) }
            return args.removeFirst()
        }
        while !args.isEmpty {
            let a = args.removeFirst()
            switch a {
            case "--bin": bin = try value(a)
            case "--card": card = try value(a)
            case "--out": out = try value(a)
            case "--only": only = try value(a)
            case "--repo-root": root = try value(a)
            case "--dry-run": dryRun = true
            case "--force": force = true
            case "--allow-hash-mismatch": allowMismatch = true
            case "--allow-outside-private-assets": allowOutside = true
            case "--transparent-key":
                let v = try value(a)
                let digits = v.lowercased().hasPrefix("0x") ? String(v.dropFirst(2)) : v
                guard let n = UInt16(digits, radix: 16) else { throw CommandLineError.invalidValue(flag: a, value: v) }
                key = n
            case "-h", "--help": return nil
            default: throw CommandLineError.unknownArgument(a)
            }
        }
        guard let bin, let card, let out else { throw CommandLineError.missingRequired }
        var options = ExtractOptions(binURL: URL(fileURLWithPath: bin), card: card, outDirectory: URL(fileURLWithPath: out))
        options.dryRun = dryRun
        options.force = force
        options.allowHashMismatch = allowMismatch
        options.allowOutsidePrivateAssets = allowOutside
        options.transparentKey = key
        options.only = only
        options.repoRoot = root.map { URL(fileURLWithPath: $0) }
        return options
    }
}
