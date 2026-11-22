import Testing
import Foundation
@testable import DigiWalkerCore

@Suite struct RGBA8Tests {
    @Test func parsesRGB() { #expect(RGBA8(hex: "#1B1B2F") == RGBA8(r: 0x1B, g: 0x1B, b: 0x2F, a: 255)) }
    @Test func parsesAlpha() {
        #expect(RGBA8(hex: "#00000000")?.isTransparent == true)
        #expect(RGBA8(hex: "#11223380")?.a == 0x80)
    }
    @Test(arguments: ["", "#", "123456", "#12345", "#GGGGGG", "#1234567"])
    func rejectsBad(_ s: String) { #expect(RGBA8(hex: s) == nil) }
}

@Suite struct ValidationTests {
    @Test func validPackHasNoIssues() { #expect(Fixtures.pack().validate().isEmpty) }

    @Test func rowCount() {
        var s = Fixtures.sheet()
        s.animations["idle"]!.frames[0].removeLast()
        #expect(!s.validate().isEmpty)
    }
    @Test func rowLength() {
        var s = Fixtures.sheet()
        s.animations["idle"]!.frames[0][1] = "aab"
        #expect(s.validate().contains { $0.row == 1 })
    }
    @Test func undefinedCharacter() {
        var s = Fixtures.sheet()
        s.animations["idle"]!.frames[1][2] = "..z."
        #expect(s.validate().contains { $0.message.contains("z") })
    }
    @Test func paletteKeyMustBeOneChar() {
        let s = Fixtures.sheet(palette: [".": "#00000000", "a": "#FF0000", "b": "#00FF00", "ab": "#000000"])
        #expect(!s.validate().isEmpty)
    }
    @Test func paletteColorMustParse() {
        let s = Fixtures.sheet(palette: [".": "#00000000", "a": "red", "b": "#00FF00"])
        #expect(!s.validate().isEmpty)
    }
    @Test func sizeRange() {
        #expect(!Fixtures.sheet(size: 0, animations: ["idle": .init(frameDuration: 1, frames: [[]])]).validate().isEmpty)
        #expect(!Fixtures.sheet(size: 65).validate().isEmpty)
    }
    @Test func idleRequired() {
        #expect(!Fixtures.sheet(animations: ["happy": .init(frameDuration: 1, frames: [])]).validate().isEmpty)
        #expect(!Fixtures.sheet(animations: ["idle": .init(frameDuration: 1, frames: [])]).validate().isEmpty)
    }
    @Test func emptyFramesAllowedOutsideIdle() {
        #expect(Fixtures.sheet().validate().isEmpty)
    }
    @Test func frameDurationPositive() {
        var s = Fixtures.sheet()
        s.animations["idle"]!.frameDuration = 0
        #expect(!s.validate().isEmpty)
    }
    @Test func duplicateSpeciesId() {
        let p = Fixtures.pack([Fixtures.sheet(), Fixtures.sheet(evolvesTo: nil, level: nil)])
        #expect(p.validate().contains { $0.message.contains("중복") })
    }
    @Test func evolvesToMustExist() {
        let p = Fixtures.pack([Fixtures.sheet(evolvesTo: "ghost")])
        #expect(p.validate().contains { $0.message.contains("ghost") })
    }
    @Test func evolvesToNotSelf() {
        let p = Fixtures.pack([Fixtures.sheet(evolvesTo: "s1")])
        #expect(!p.validate().isEmpty)
    }
    @Test func evolvePairTogether() {
        #expect(!Fixtures.sheet(evolvesTo: "s2", level: nil).validate().isEmpty)
        #expect(!Fixtures.sheet(evolvesTo: nil, level: 5).validate().isEmpty)
    }
    @Test func evolveLevelAtLeastTwo() {
        #expect(!Fixtures.sheet(level: 1).validate().isEmpty)
        #expect(Fixtures.sheet(level: 2).validate().isEmpty)
    }
    @Test func frameDurationBounds() {
        for d in [1e-12, 0.01, 11, .infinity, .nan, -1] {
            var s = Fixtures.sheet()
            s.animations["idle"]!.frameDuration = d
            #expect(!s.validate().isEmpty, "\(d)")
        }
        for d in [0.05, 10] {
            var s = Fixtures.sheet()
            s.animations["idle"]!.frameDuration = d
            #expect(s.validate().isEmpty)
        }
    }
    @Test func evolutionCycleRejected() {
        let p = Fixtures.pack([Fixtures.sheet(id: "s1", evolvesTo: "s2"), Fixtures.sheet(id: "s2", evolvesTo: "s1")])
        #expect(p.validate().contains { $0.message.contains("순환") })
        let chain = Fixtures.pack([Fixtures.sheet(id: "s1", evolvesTo: "s2"), Fixtures.sheet(id: "s2", evolvesTo: "s3"), Fixtures.sheet(id: "s3", evolvesTo: nil, level: nil)])
        #expect(chain.validate().isEmpty)
    }
    @Test func starterMustExist() {
        #expect(!Fixtures.pack(starter: "nope").validate().isEmpty)
    }
}

@Suite struct DecodeTests {
    @Test func runMerging() {
        let a = RGBA8(r: 255, g: 0, b: 0)
        let b = RGBA8(r: 0, g: 255, b: 0)
        let t = RGBA8(r: 0, g: 0, b: 0, a: 0)
        // 전부 투명
        #expect(DecodedFrame(size: 2, pixels: [t, t, t, t]).runs.isEmpty)
        // 한 색
        #expect(DecodedFrame(size: 2, pixels: [a, a, a, a]).runs == [
            PixelRun(y: 0, x: 0, length: 2, color: a), PixelRun(y: 1, x: 0, length: 2, color: a),
        ])
        // 교차 패턴
        #expect(DecodedFrame(size: 3, pixels: [a, b, a, t, t, t, t, t, t]).runs.count == 3)
        // 행 경계: 행 끝과 다음 행 처음이 같은 색이어도 병합하지 않음
        #expect(DecodedFrame(size: 2, pixels: [t, a, a, t]).runs == [
            PixelRun(y: 0, x: 1, length: 1, color: a), PixelRun(y: 1, x: 0, length: 1, color: a),
        ])
    }

    @Test func snapshot() throws {
        let lib = try SpriteLibrary(pack: Fixtures.pack())
        let idle = try #require(lib.starter?.idle)
        let frame = idle.frames[0]
        let r = RGBA8(r: 255, g: 0, b: 0)
        let g = RGBA8(r: 0, g: 255, b: 0, a: 0x80)
        let t = RGBA8(r: 0, g: 0, b: 0, a: 0)
        #expect(frame.pixels == [
            r, t, g, t,
            r, r, g, g,
            t, t, t, t,
            g, g, g, g,
        ])
        #expect(frame.runs.count == 5)
        #expect(idle.frames.count == 2)
        #expect(lib.species(id: "s2") != nil)
    }

    @Test func invalidPackThrows() {
        #expect(throws: SpritePackError.self) { try SpriteLibrary(pack: Fixtures.pack(starter: "x")) }
    }

    @Test func frameIndexByElapsedTime() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        #expect(frameIndex(at: t0, frameDuration: 0.5, frameCount: 2) == 0)
        #expect(frameIndex(at: t0.addingTimeInterval(0.6), frameDuration: 0.5, frameCount: 2) == 1)
        #expect(frameIndex(at: t0.addingTimeInterval(1.1), frameDuration: 0.5, frameCount: 2) == 0)
        #expect(frameIndex(at: t0.addingTimeInterval(0.6), frameDuration: 0.5, frameCount: 2, paused: true) == 0)
        #expect(frameIndex(at: t0.addingTimeInterval(0.6), frameDuration: 0.5, frameCount: 1) == 0)
    }

    @Test func frameIndexNeverTraps() {
        let d = Date(timeIntervalSinceReferenceDate: 7.7e8)
        for dur in [1e-12, 1e-300, .leastNonzeroMagnitude, .infinity, .nan, -1, 0] {
            let i = frameIndex(at: d, frameDuration: dur, frameCount: 3)
            #expect((0..<3).contains(i))
        }
        #expect(frameIndex(at: .distantPast, frameDuration: 0.5, frameCount: 3) >= 0)
        #expect(frameIndex(at: .distantFuture, frameDuration: 1e-9, frameCount: 3) >= 0)
    }

    @Test func frameIndexBeyondInt32Ticks() {
        // tick = 6e9 (> Int32.max), frameDuration 0.25, 3 frames → 6_000_000_000 % 3 == 0
        let t = Date(timeIntervalSinceReferenceDate: 2_000_000_000 * 0.25 * 3)
        #expect(frameIndex(at: t, frameDuration: 0.25, frameCount: 3) == 0)
        #expect(frameIndex(at: t.addingTimeInterval(0.25), frameDuration: 0.25, frameCount: 3) == 1)
        #expect(frameIndex(at: t.addingTimeInterval(0.5), frameDuration: 0.25, frameCount: 3) == 2)
        let neg = Date(timeIntervalSinceReferenceDate: -2_000_000_000 * 0.25 * 3 - 0.25)
        #expect(frameIndex(at: neg, frameDuration: 0.25, frameCount: 3) == 2)
    }

    @Test func pixelScale() {
        #expect(integerPixelScale(spriteSize: 32, availableWidth: 205, availableHeight: 150) == 4)
        #expect(integerPixelScale(spriteSize: 64, availableWidth: 205, availableHeight: 150) == 2)
        #expect(integerPixelScale(spriteSize: 32, availableWidth: 100, availableHeight: 150) == 3)
        #expect(integerPixelScale(spriteSize: 64, availableWidth: 40, availableHeight: 40) == 1)
        #expect(integerPixelScale(spriteSize: 8, availableWidth: 200, availableHeight: 200) == 4)
        #expect(integerPixelScale(spriteSize: 0, availableWidth: 200, availableHeight: 200) == 1)
    }
}

@Suite struct LoadingTests {
    @Test func privateValidWins() throws {
        let root = Fixtures.tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        var priv = Fixtures.pack(); priv.packId = "private"
        try Fixtures.write(priv, to: root.appendingPathComponent("P"))
        try Fixtures.write(Fixtures.pack(), to: root.appendingPathComponent("S"))
        let r = try SpritePackResolver.resolve(candidates: [root.appendingPathComponent("P"), root.appendingPathComponent("S")])
        #expect(r.library.packId == "private")
        #expect(r.skipped.isEmpty)
    }
    @Test func privateMissingFallsBack() throws {
        let root = Fixtures.tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("P"), withIntermediateDirectories: true)
        try Fixtures.write(Fixtures.pack(), to: root.appendingPathComponent("S"))
        let r = try SpritePackResolver.resolve(candidates: [root.appendingPathComponent("P"), root.appendingPathComponent("S")])
        #expect(r.library.packId == "fixture")
        #expect(r.skipped.count == 1)
    }
    @Test func privateCorruptFallsBack() throws {
        let root = Fixtures.tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let p = root.appendingPathComponent("P")
        try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: p.appendingPathComponent("pack.json"))
        try Fixtures.write(Fixtures.pack(), to: root.appendingPathComponent("S"))
        let r = try SpritePackResolver.resolve(candidates: [p, root.appendingPathComponent("S")])
        #expect(r.sourceDirectory.lastPathComponent == "S")
        #expect(r.skipped.count == 1)
    }
    @Test func privateInvalidFallsBack() throws {
        let root = Fixtures.tempDir(); defer { try? FileManager.default.removeItem(at: root) }
        try Fixtures.write(Fixtures.pack(starter: "nope"), to: root.appendingPathComponent("P"))
        try Fixtures.write(Fixtures.pack(), to: root.appendingPathComponent("S"))
        let r = try SpritePackResolver.resolve(candidates: [root.appendingPathComponent("P"), root.appendingPathComponent("S")])
        #expect(r.sourceDirectory.lastPathComponent == "S")
    }
    @Test func allFail() {
        let root = Fixtures.tempDir()
        #expect(throws: SpritePackResolutionFailure.self) {
            try SpritePackResolver.resolve(candidates: [root.appendingPathComponent("P"), root.appendingPathComponent("S")])
        }
        #expect(throws: SpritePackResolutionFailure.self) { try SpritePackResolver.resolve(candidates: []) }
    }
}

@Suite struct RepositoryPackTests {
    static var repoRoot: URL {
        // Packages/DigiWalkerCore/Tests/DigiWalkerCoreTests/SpriteTests.swift → 저장소 루트
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test func starterPackIsValid() throws {
        let dir = Self.repoRoot.appendingPathComponent("Assets/StarterPack")
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("pack.json").path) else {
            Issue.record("Assets/StarterPack/pack.json 이 없다 (필수 폴백)")
            return
        }
        let lib = try SpritePackLoader.load(directory: dir)
        #expect(lib.species.count == 2)
        #expect(lib.species.allSatisfy { $0.size == 32 })
        #expect(lib.starter?.evolvesTo != nil)
    }

    @Test func privatePackIsValidIfPresent() throws {
        let dir = Self.repoRoot.appendingPathComponent("PrivateAssets")
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("pack.json").path) else { return }
        // 개인 팩 내용은 출력하지 않는다. 성공 여부(bool)만 판정한다.
        let ok = (try? SpritePackLoader.load(directory: dir)) != nil
        #expect(ok, "PrivateAssets/pack.json 검증 실패 (내용은 출력하지 않음)")
    }
}
