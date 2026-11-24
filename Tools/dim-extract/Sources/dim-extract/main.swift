import DIMCardFormat
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let options: ExtractOptions
do {
    guard let parsed = try CommandLineOptions.parse(Array(CommandLine.arguments.dropFirst())) else {
        print(CommandLineOptions.usage)
        exit(0)
    }
    options = parsed
} catch {
    fail("\(error)\n\(CommandLineOptions.usage)")
}

do {
    let report = try Extractor.run(options)
    print("card \(report.card)  sha256[0..16]=\(report.shaPrefix)  catalog-match=\(report.hashMatches)")
    for w in report.warnings { print("warning: \(w)") }
    print("species | index | frame | sheet | result")
    var written = 0, existing = 0, shared = 0
    for r in report.results {
        let text: String
        switch r.outcome {
        case .wrote: text = "wrote"
        case .wouldWrite: text = "would write (dry run)"
        case .skippedExisting: text = "skipped (exists, use --force)"
        case .skippedShared(let base): text = "skipped (shared, base card \(base))"
        }
        switch r.outcome {
        case .wrote, .wouldWrite: written += 1
        case .skippedExisting: existing += 1
        case .skippedShared: shared += 1
        }
        print("\(r.speciesId) | \(r.dimIndex) | \(r.frameSize)x\(r.frameCount) | \(r.output) | \(text)")
    }
    print("summary: \(options.dryRun ? "would-write" : "written")=\(written) skipped-existing=\(existing) skipped-shared=\(shared)")
} catch {
    fail("\(error)")
}
