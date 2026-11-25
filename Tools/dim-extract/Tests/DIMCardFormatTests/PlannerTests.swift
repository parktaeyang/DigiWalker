import CryptoKit
import DigiWalkerCore
import Foundation
import Testing
@testable import DIMCardFormat

struct PlannerTests {
    @Test func sharedSpeciesAreWrittenFromAgumonOnly() throws {
        let agu = try SheetPlanner.plan(card: .agumonEX, image: DIMCardImage(raw: SyntheticCard().build(card: .agumonEX)))
        let gabu = try SheetPlanner.plan(card: .gabumonEX, image: DIMCardImage(raw: SyntheticCard().build(card: .gabumonEX)))
        let guil = try SheetPlanner.plan(card: .guilmonEX, image: DIMCardImage(raw: SyntheticCard().build(card: .guilmonEX)))
        #expect(agu.filter { $0.action == .write }.count == 17)
        #expect(gabu.filter { $0.action == .write }.count == 15)
        #expect(guil.filter { $0.action == .write }.count == 17)
        let skipped = gabu.filter { $0.action != .write }.map(\.speciesId).sorted()
        #expect(skipped == ["algomon_adult", "omegamon"])
        #expect(gabu.first { $0.speciesId == "omegamon" }?.action == .skipShared(baseCard: "agu_ex"))
        #expect(agu.first { $0.speciesId == "omegamon" }?.action == .write)
    }

    @Test func allElevenCardsPlanAgainstSyntheticBins() throws {
        for card in SpeciesCatalog.cards {
            let image = try DIMCardImage(raw: SyntheticCard().build(card: card))
            let sheets = try SheetPlanner.plan(card: card, image: image)
            #expect(sheets.count == 17, "\(card.id)")
            for sheet in sheets where sheet.action == .write {
                #expect(sheet.frames.count == sheet.spec.frameCount)
                #expect(sheet.sheetWidth == sheet.spec.frameWidth * sheet.spec.frameCount)
            }
        }
    }

    @Test func wolfmonSkipsSharedBotamonAndSusanoomon() throws {
        let sheets = try SheetPlanner.plan(card: .wolfmonEX, image: DIMCardImage(raw: SyntheticCard().build(card: .wolfmonEX)))
        #expect(sheets.filter { $0.action == .write }.count == 15)
        #expect(sheets.first { $0.speciesId == "botamon" }?.action == .skipShared(baseCard: "agu_ex"))
        #expect(sheets.first { $0.speciesId == "susanoomon" }?.action == .skipShared(baseCard: "agni_ex"))
        #expect(sheets.filter { $0.action != .write }.count == 2)
    }

    @Test func agnimonWritesSusanoomonAsBaseCard() throws {
        let sheets = try SheetPlanner.plan(card: .agnimonEX, image: DIMCardImage(raw: SyntheticCard().build(card: .agnimonEX)))
        #expect(sheets.filter { $0.action == .write }.count == 17)
        #expect(sheets.first { $0.speciesId == "susanoomon" }?.action == .write)
    }

    @Test func frontierLayoutHasTwoStageTwoSlotsAnd233Sprites() throws {
        let card = EvolutionCard.agnimonEX
        #expect(card.stages[2].count == 2)
        let image = try DIMCardImage(raw: SyntheticCard().build(card: card))
        #expect(image.spriteCount == 233)
        let sheets = try SheetPlanner.plan(card: card, image: image)
        for slot in card.stages[2] {
            let sheet = try #require(sheets.first { $0.speciesId == slot.speciesId })
            #expect(sheet.sheetWidth == 768 && sheet.sheetHeight == 56)
        }
        // Louwemon: stage 4 has six species and stage 5 three.
        #expect(EvolutionCard.louwemonEX.stages.map(\.count) == [1, 1, 2, 4, 6, 3])
        let louwe = try DIMCardImage(raw: SyntheticCard().build(card: .louwemonEX))
        #expect(louwe.spriteCount == 233)
    }

    @Test func sheetsFollowCoreSpec() throws {
        let sheets = try SheetPlanner.plan(card: .agumonEX, image: DIMCardImage(raw: SyntheticCard().build(card: .agumonEX)))
        let botamon = try #require(sheets.first { $0.speciesId == "botamon" })
        #expect(botamon.sheetWidth == 160 && botamon.sheetHeight == 24 && botamon.frames.count == 5)
        let greymon = try #require(sheets.first { $0.speciesId == "greymon" })
        #expect(greymon.sheetWidth == 768 && greymon.sheetHeight == 56 && greymon.frames.count == 12)
    }

    @Test func assemblesFramesInOneRowAndKeysTransparency() throws {
        let image = try DIMCardImage(raw: SyntheticCard().build(card: .agumonEX))
        var sheet = try #require(SheetPlanner.plan(card: .agumonEX, image: image).first { $0.speciesId == "botamon" })
        // Make one pixel of frame 3 the transparency key.
        var px = sheet.frames[3].pixels
        px[0] = RGB565.defaultTransparentKey
        var frames = sheet.frames
        frames[3] = DIMSprite(width: 32, height: 24, pixels: px)
        sheet = PlannedSheet(speciesId: sheet.speciesId, dimIndex: sheet.dimIndex, spec: sheet.spec, action: .write,
                             sheetWidth: sheet.sheetWidth, sheetHeight: sheet.sheetHeight, frames: frames)
        let rgba = SheetPlanner.assemble(sheet, transparentKey: RGB565.defaultTransparentKey)
        #expect(rgba.count == 160 * 24 * 4)
        #expect(Array(rgba[((3 * 32) * 4)..<((3 * 32) * 4 + 4)]) == [0, 0, 0, 0])
        // Frame 4, row 5, column 7 lands at x = 4 * 32 + 7.
        let o = (5 * 160 + 4 * 32 + 7) * 4
        #expect(Array(rgba[o..<(o + 4)]) == RGB565.rgba(frames[4].pixels[5 * 32 + 7]))
    }

    @Test func mismatchesFailBeforeAnyOutput() throws {
        var stage = SyntheticCard(); stage.stageOverride = [3: 4]
        #expect(throws: PlanError.self) { try SheetPlanner.plan(card: .agumonEX, image: DIMCardImage(raw: stage.build(card: .agumonEX))) }
        var extra = SyntheticCard(); extra.extraSprite = true
        #expect(throws: PlanError.self) { try SheetPlanner.plan(card: .agumonEX, image: DIMCardImage(raw: extra.build(card: .agumonEX))) }
        var size = SyntheticCard(); size.sizeOverride = [10 + 6 + 7 + 2 + 5: (60, 56)] // a Greymon frame
        #expect(throws: PlanError.self) { try SheetPlanner.plan(card: .agumonEX, image: DIMCardImage(raw: size.build(card: .agumonEX))) }
        let image = try DIMCardImage(raw: SyntheticCard().build(card: .agumonEX))
        #expect(throws: PlanError.unknownSpecies("nope")) { try SheetPlanner.plan(card: .agumonEX, image: image, only: "nope") }
    }

    @Test func resolvesCardsByChartOrCatalogId() throws {
        #expect(try SheetPlanner.resolveCard("agu_ex").id == "agu_ex")
        #expect(try SheetPlanner.resolveCard("5e133fc75fc90377").id == "gabu_ex")
        for card in SpeciesCatalog.cards {
            #expect(try SheetPlanner.resolveCard(card.id).id == card.id)
            #expect(try SheetPlanner.resolveCard(card.catalogCardId).id == card.id)
        }
        #expect(try SheetPlanner.resolveCard("wolf_ex").catalogCardId == "2661974b34f571f5")
        #expect(try SheetPlanner.resolveCard("b8a262b73a584fa2").id == "terrier_ex")
        #expect(throws: PlanError.unknownCard("zzz")) { try SheetPlanner.resolveCard("zzz") }
    }
}

struct ExtractorTests {
    func makeEnv(card: EvolutionCard = .agumonEX) throws -> (bin: URL, out: URL, dir: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dimx-\(UUID().uuidString)")
        let out = dir.appendingPathComponent("PrivateAssets/dim")
        try Self.makeFakeRoot(dir)
        let bin = dir.appendingPathComponent("card.bin")
        try SyntheticCard().build(card: card).write(to: bin)
        return (bin, out, dir)
    }

    static func makeFakeRoot(_ dir: URL) throws {
        let tools = dir.appendingPathComponent("Tools/dim-extract")
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        try Data().write(to: tools.appendingPathComponent("Package.swift"))
    }

    func files(_ out: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: out.path)) ?? []).sorted()
    }

    @Test func hashMismatchIsRefusedWithoutFlag() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.dir) }
        var opts = ExtractOptions(binURL: env.bin, card: "agu_ex", outDirectory: env.out)
        opts.repoRoot = env.dir
        #expect(throws: ExtractError.self) { try Extractor.run(opts) }
        #expect(files(env.out).isEmpty)
        opts.allowHashMismatch = true
        let report = try Extractor.run(opts)
        #expect(!report.hashMatches && !report.warnings.isEmpty)
        #expect(files(env.out).count == 17)
    }

    @Test func dryRunWritesNothing() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.dir) }
        var opts = ExtractOptions(binURL: env.bin, card: "agu_ex", outDirectory: env.out)
        opts.repoRoot = env.dir
        opts.allowHashMismatch = true
        opts.dryRun = true
        let report = try Extractor.run(opts)
        #expect(report.results.filter { $0.outcome == .wouldWrite }.count == 17)
        #expect(!FileManager.default.fileExists(atPath: env.out.path))
    }

    @Test func existingFilesAreKeptUnlessForced() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.dir) }
        try FileManager.default.createDirectory(at: env.out, withIntermediateDirectories: true)
        let marker = env.out.appendingPathComponent("agumon.png")
        try Data("keep".utf8).write(to: marker)
        var opts = ExtractOptions(binURL: env.bin, card: "agu_ex", outDirectory: env.out)
        opts.repoRoot = env.dir
        opts.allowHashMismatch = true
        let first = try Extractor.run(opts)
        #expect(first.results.first { $0.speciesId == "agumon" }?.outcome == .skippedExisting)
        #expect(try Data(contentsOf: marker) == Data("keep".utf8))
        opts.force = true
        _ = try Extractor.run(opts)
        #expect(try Data(contentsOf: marker).starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(files(env.out).allSatisfy { $0.hasSuffix(".png") })
    }

    @Test func gabumonSkipsSharedSpeciesAndWritesSizedPNGs() throws {
        let env = try makeEnv(card: .gabumonEX)
        defer { try? FileManager.default.removeItem(at: env.dir) }
        var opts = ExtractOptions(binURL: env.bin, card: "gabu_ex", outDirectory: env.out)
        opts.repoRoot = env.dir
        opts.allowHashMismatch = true
        let report = try Extractor.run(opts)
        #expect(report.results.count == 17)
        let names = files(env.out)
        #expect(names.count == 15 && !names.contains("omegamon.png") && !names.contains("algomon_adult.png"))
        let png = try Data(contentsOf: env.out.appendingPathComponent("gabumon.png"))
        let decoded = try PNGWriterTests.decode(png)
        #expect(decoded.w == 768 && decoded.h == 56)
    }

    @Test func wolfmonRunKeepsExistingFilesAndAddsOnlyNewOnes() throws {
        let env = try makeEnv(card: .wolfmonEX)
        defer { try? FileManager.default.removeItem(at: env.dir) }
        try FileManager.default.createDirectory(at: env.out, withIntermediateDirectories: true)
        let existing = ["botamon.png", "susanoomon.png", "agumon.png"]
        for name in existing { try Data("keep-\(name)".utf8).write(to: env.out.appendingPathComponent(name)) }
        var opts = ExtractOptions(binURL: env.bin, card: "wolf_ex", outDirectory: env.out)
        opts.repoRoot = env.dir
        opts.allowHashMismatch = true
        let report = try Extractor.run(opts)
        #expect(report.results.filter { $0.outcome == .skippedExisting }.isEmpty)
        #expect(report.results.first { $0.speciesId == "botamon" }?.outcome == .skippedShared(baseCard: "agu_ex"))
        #expect(report.results.first { $0.speciesId == "susanoomon" }?.outcome == .skippedShared(baseCard: "agni_ex"))
        #expect(report.results.filter { if case .skippedShared = $0.outcome { true } else { false } }.count == 2)
        for name in existing { #expect(try Data(contentsOf: env.out.appendingPathComponent(name)) == Data("keep-\(name)".utf8)) }
        #expect(files(env.out).count == 15 + existing.count)
        #expect(try Data(contentsOf: env.out.appendingPathComponent("wolfmon.png")).starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func invalidSpecLeavesNoPartialOutput() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dimx-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.makeFakeRoot(dir)
        var synth = SyntheticCard(); synth.stageOverride = [16: 4]
        let bin = dir.appendingPathComponent("bad.bin")
        try synth.build(card: .agumonEX).write(to: bin)
        var opts = ExtractOptions(binURL: bin, card: "agu_ex", outDirectory: dir.appendingPathComponent("PrivateAssets/out"))
        opts.repoRoot = dir
        opts.allowHashMismatch = true
        #expect(throws: PlanError.self) { try Extractor.run(opts) }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("PrivateAssets/out").path))
    }

    @Test func outputOutsidePrivateAssetsIsRefusedUnlessAllowed() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.dir) }
        var opts = ExtractOptions(binURL: env.bin, card: "agu_ex", outDirectory: env.dir.appendingPathComponent("elsewhere"))
        opts.allowHashMismatch = true
        opts.repoRoot = env.dir
        #expect(throws: ExtractError.self) { try Extractor.run(opts) }
        #expect(!FileManager.default.fileExists(atPath: env.dir.appendingPathComponent("elsewhere").path))
        opts.allowOutsidePrivateAssets = true
        opts.dryRun = true
        _ = try Extractor.run(opts)
    }

    @Test func symlinkedOutputThatEscapesPrivateAssetsIsRefused() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.dir) }
        let fm = FileManager.default
        let outside = env.dir.appendingPathComponent("outside")
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try fm.createDirectory(at: env.dir.appendingPathComponent("PrivateAssets"), withIntermediateDirectories: true)
        let link = env.dir.appendingPathComponent("PrivateAssets/dim")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        var opts = ExtractOptions(binURL: env.bin, card: "agu_ex", outDirectory: link)
        opts.allowHashMismatch = true
        opts.repoRoot = env.dir
        #expect(throws: ExtractError.self) { try Extractor.run(opts) }
        #expect(files(outside).isEmpty)
    }

    @Test func repoRootMustLookLikeTheRepository() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.dir) }
        var opts = ExtractOptions(binURL: env.bin, card: "agu_ex", outDirectory: env.out)
        opts.allowHashMismatch = true
        opts.repoRoot = env.dir.appendingPathComponent("Tools")
        #expect(throws: ExtractError.self) { try Extractor.run(opts) }
        #expect(!FileManager.default.fileExists(atPath: env.out.path))
    }

    @Test func privateAssetsThatIsASymlinkIsRefused() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.dir) }
        let fm = FileManager.default
        let elsewhere = env.dir.appendingPathComponent("elsewhere")
        try fm.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: env.dir.appendingPathComponent("PrivateAssets"), withDestinationURL: elsewhere)
        var opts = ExtractOptions(binURL: env.bin, card: "agu_ex", outDirectory: env.out)
        opts.allowHashMismatch = true
        opts.repoRoot = env.dir
        opts.dryRun = true
        #expect(throws: ExtractError.privateAssetsIsLink) { try Extractor.run(opts) }
        #expect(files(elsewhere).isEmpty)
    }

    @Test func dryRunStillRequiresADirectoryOutput() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.dir) }
        let fm = FileManager.default
        try fm.createDirectory(at: env.dir.appendingPathComponent("PrivateAssets"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: env.dir.appendingPathComponent("PrivateAssets/dim"))
        var opts = ExtractOptions(binURL: env.bin, card: "agu_ex", outDirectory: env.out)
        opts.allowHashMismatch = true
        opts.repoRoot = env.dir
        opts.dryRun = true
        #expect(throws: ExtractError.self) { try Extractor.run(opts) }
    }

    @Test func commitWithoutReplaceNeverOverwrites() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dimx-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let target = dir.appendingPathComponent("a.png"), tmp = dir.appendingPathComponent(".a.tmp")
        try Data("new".utf8).write(to: tmp)
        try Data("old".utf8).write(to: target)
        #expect(try Extractor.commit(tmp: tmp, to: target, replace: false) == false)
        #expect(try Data(contentsOf: target) == Data("old".utf8))
        let fresh = dir.appendingPathComponent("b.png")
        #expect(try Extractor.commit(tmp: tmp, to: fresh, replace: false))
        #expect(try Data(contentsOf: fresh) == Data("new".utf8))
        try Data("newer".utf8).write(to: dir.appendingPathComponent(".c.tmp"))
        #expect(try Extractor.commit(tmp: dir.appendingPathComponent(".c.tmp"), to: target, replace: true))
        #expect(try Data(contentsOf: target) == Data("newer".utf8))
    }

    @Test func otherCardsBinIsRejectedEvenWithHashOverride() throws {
        let env = try makeEnv(card: .gabumonEX)
        defer { try? FileManager.default.removeItem(at: env.dir) }
        var opts = ExtractOptions(binURL: env.bin, card: "agu_ex", outDirectory: env.out)
        opts.allowHashMismatch = true
        opts.repoRoot = env.dir
        #expect(throws: ExtractError.dimIdMismatch(actual: 13, expected: 12, card: "agu_ex")) { try Extractor.run(opts) }
        #expect(!FileManager.default.fileExists(atPath: env.out.path))
    }

    @Test func forceReplacesOnlyRegularFiles() throws {
        let env = try makeEnv()
        defer { try? FileManager.default.removeItem(at: env.dir) }
        let fm = FileManager.default
        try fm.createDirectory(at: env.out, withIntermediateDirectories: true)
        var opts = ExtractOptions(binURL: env.bin, card: "agu_ex", outDirectory: env.out)
        opts.allowHashMismatch = true
        opts.repoRoot = env.dir
        opts.force = true
        // directory in place of a sheet
        try fm.createDirectory(at: env.out.appendingPathComponent("agumon.png"), withIntermediateDirectories: true)
        #expect(throws: ExtractError.notRegularFile("agumon.png")) { try Extractor.run(opts) }
        #expect(files(env.out) == ["agumon.png"])
        try fm.removeItem(at: env.out.appendingPathComponent("agumon.png"))
        // symlink in place of a sheet (the target must stay untouched)
        let target = env.dir.appendingPathComponent("precious.txt")
        try Data("x".utf8).write(to: target)
        try fm.createSymbolicLink(at: env.out.appendingPathComponent("agumon.png"), withDestinationURL: target)
        #expect(throws: ExtractError.notRegularFile("agumon.png")) { try Extractor.run(opts) }
        #expect(try Data(contentsOf: target) == Data("x".utf8))
        #expect(files(env.out) == ["agumon.png"])
    }

    @Test func oversizedInputIsRejectedBeforeHashing() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dimx-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.makeFakeRoot(dir)
        let bin = dir.appendingPathComponent("big.bin")
        try Data(count: DIMCardImage.imageSize + 1).write(to: bin)
        var opts = ExtractOptions(binURL: bin, card: "agu_ex", outDirectory: dir.appendingPathComponent("PrivateAssets/dim"))
        opts.repoRoot = dir
        // With a size error the hash mismatch error must not be the one reported.
        #expect(throws: DIMFormatError.wrongImageSize(DIMCardImage.imageSize + 1)) { try Extractor.run(opts) }
    }
}

struct CommandLineTests {
    @Test func parsesFullCommandLine() throws {
        let o = try #require(try CommandLineOptions.parse(["--bin", "a.bin", "--card", "agu_ex", "--out", "o", "--dry-run",
                                                           "--force", "--transparent-key", "0x1234", "--only", "agumon"]))
        #expect(o.dryRun && o.force && o.transparentKey == 0x1234 && o.only == "agumon")
        #expect(try CommandLineOptions.parse(["--help"]) == nil)
    }

    @Test func optionValuesCannotBeFlags() {
        #expect(throws: CommandLineError.missingValue("--out")) {
            try CommandLineOptions.parse(["--bin", "a", "--card", "agu_ex", "--out", "--dry-run"])
        }
        #expect(throws: CommandLineError.missingValue("--bin")) { try CommandLineOptions.parse(["--bin"]) }
        #expect(throws: CommandLineError.unknownArgument("--nope")) { try CommandLineOptions.parse(["--nope"]) }
        #expect(throws: CommandLineError.missingRequired) { try CommandLineOptions.parse(["--dry-run"]) }
        #expect(throws: CommandLineError.invalidValue(flag: "--transparent-key", value: "zz")) {
            try CommandLineOptions.parse(["--transparent-key", "zz"])
        }
    }
}
