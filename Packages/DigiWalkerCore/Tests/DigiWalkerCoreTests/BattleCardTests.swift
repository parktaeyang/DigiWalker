import Foundation
import Testing
@testable import DigiWalkerCore

struct BattleCardTests {
    private func card(_ id: String) -> BattleCard {
        let info = SpeciesCatalog.info(id: id)!
        return BattleCard(speciesId: id, name: info.name)!
    }

    private func error(_ text: String) -> BattleCardError? {
        if case .failure(let e) = BattleCard.decode(text) { return e }
        return nil
    }

    private let agu = "digiwalker-battle:1?s=agumon&t=2&n=%EC%95%84%EA%B5%AC%EB%AA%AC"

    @Test func stageLookup() {
        #expect(SpeciesCatalog.battleStage(of: "botamon") == 0)
        #expect(SpeciesCatalog.battleStage(of: "agumon") == 2)
        #expect(SpeciesCatalog.battleStage(of: "wargreymon") == 5)
        #expect(SpeciesCatalog.battleStage(of: SpeciesCatalog.eggId) == nil)
        #expect(SpeciesCatalog.battleStage(of: SpeciesCatalog.legacyPoyomonId) == nil)
        #expect(SpeciesCatalog.battleStage(of: "nope") == nil)
    }

    @Test func sharedSpeciesHaveOneStage() {
        let shared = SpeciesCatalog.cardSpeciesIds.filter { id in
            SpeciesCatalog.cards.filter { $0.stage(of: id) != nil }.count > 1
        }
        #expect(shared.count == 4)
        for id in shared {
            #expect(Set(SpeciesCatalog.cards.compactMap { $0.stage(of: id) }).count == 1, "\(id)")
        }
    }

    @Test func everyCardSpeciesRoundTripsAsAsciiWithinLimit() {
        for id in SpeciesCatalog.cardSpeciesIds {
            let original = card(id)
            let text = original.encoded()
            #expect(text.utf8.allSatisfy { $0 < 128 }, "\(id)")
            #expect(text.utf8.count <= BattleCard.maxPayloadBytes, "\(id)")
            #expect(BattleCard.decode(text) == .success(original), "\(id)")
        }
    }

    @Test func exampleFormat() {
        #expect(card("agumon").encoded() == agu)
        #expect(BattleCard.decode(agu) == .success(card("agumon")))
    }

    @Test func payloadKeysAreOnlySTN() {
        let query = card("agumon").encoded().split(separator: "?")[1]
        let keys = Set(query.split(separator: "&").map { $0.split(separator: "=")[0] })
        #expect(keys == ["s", "t", "n"])
    }

    @Test func cannotBuildEggOrStagelessCards() {
        #expect(BattleCard(speciesId: SpeciesCatalog.eggId, name: "디지타마") == nil)
        #expect(BattleCard(speciesId: SpeciesCatalog.legacyPoyomonId, name: "포요몬") == nil)
        #expect(BattleCard(speciesId: "nope", name: "x") == nil)
        #expect(BattleCard(speciesId: "agumon", name: "") == nil)
        #expect(BattleCard(speciesId: "agumon", name: String(repeating: "가", count: 33)) == nil)
    }

    @Test func tooLong() {
        let pad = String(repeating: "a", count: 513 - agu.utf8.count)
        #expect(agu.utf8.count + pad.utf8.count == 513)
        #expect(error(agu + pad) == .tooLong)
        // Exactly 512 bytes passes the length check (and fails later, as an unknown key/shape would).
        #expect(error(String(agu + pad.dropFirst())) != .tooLong)
        // The length check comes first, even for a foreign prefix.
        #expect(error(String(repeating: "x", count: 600)) == .tooLong)
    }

    @Test func notBattleCode() {
        #expect(error("https://example.com") == .notBattleCode)
        #expect(error("") == .notBattleCode)
        #expect(error("digiwalker-fight:1?s=agumon&t=2&n=a") == .notBattleCode)
    }

    @Test func malformedStructure() {
        let p = "digiwalker-battle:1?"
        #expect(error("digiwalker-battle:1") == .malformed)
        #expect(error(p + "s=agumon&t=2") == .malformed)           // missing n
        #expect(error(p + "t=2&n=a") == .malformed)                // missing s
        #expect(error(p + "s=agumon&n=a") == .malformed)           // missing t
        #expect(error(p + "s=agumon&s=agumon&t=2&n=a") == .malformed) // duplicate
        #expect(error(p + "s=agumon&t=2&n=a&x=1") == .malformed)   // unknown key
        #expect(error(p + "s=agumon&t=2&n=a&") == .malformed)      // empty part
        #expect(error(p + "s=agumon&t=2&n") == .malformed)         // no '='
        #expect(error("digiwalker-battle:?s=agumon&t=2&n=a") == .malformed)
        #expect(error("digiwalker-battle:x?s=agumon&t=2&n=a") == .malformed)
        #expect(error("digiwalker-battle:-1?s=agumon&t=2&n=a") == .malformed)
    }

    @Test func versions() {
        #expect(error("digiwalker-battle:0?s=agumon&t=2&n=a") == .unsupportedVersion(0))
        #expect(error("digiwalker-battle:2?s=agumon&t=2&n=a") == .unsupportedVersion(2))
        // A future format with other keys still reads as a version problem.
        #expect(error("digiwalker-battle:2?z=1") == .unsupportedVersion(2))
    }

    @Test func species() {
        #expect(error("digiwalker-battle:1?s=nope&t=2&n=a") == .unknownSpecies)
        #expect(error("digiwalker-battle:1?s=Agumon&t=2&n=a") == .unknownSpecies)
        #expect(error("digiwalker-battle:1?s=a%2Fb&t=2&n=a") == .unknownSpecies)
        #expect(error("digiwalker-battle:1?s=a/b&t=2&n=a") == .unknownSpecies)
        #expect(error("digiwalker-battle:1?s=" + String(repeating: "a", count: 65) + "&t=2&n=a") == .unknownSpecies)
        #expect(error("digiwalker-battle:1?s=&t=2&n=a") == .unknownSpecies)
        #expect(error("digiwalker-battle:1?s=digitama&t=0&n=a") == .egg)
        #expect(error("digiwalker-battle:1?s=poyomon&t=0&n=a") == .notEligible)
    }

    @Test func stages() {
        #expect(error("digiwalker-battle:1?s=agumon&t=3&n=a") == .stageMismatch)
        #expect(error("digiwalker-battle:1?s=agumon&t=-1&n=a") == .stageMismatch)
        #expect(error("digiwalker-battle:1?s=agumon&t=6&n=a") == .stageMismatch)
        #expect(error("digiwalker-battle:1?s=agumon&t=x&n=a") == .stageMismatch)
        #expect(error("digiwalker-battle:1?s=agumon&t=&n=a") == .stageMismatch)
    }

    @Test func names() {
        #expect(error("digiwalker-battle:1?s=agumon&t=2&n=") == .malformed)
        #expect(error("digiwalker-battle:1?s=agumon&t=2&n=" + String(repeating: "a", count: 33)) == .malformed)
        #expect(error("digiwalker-battle:1?s=agumon&t=2&n=" + String(repeating: "a", count: 32)) == nil)
        #expect(error("digiwalker-battle:1?s=agumon&t=2&n=a%00b") == .malformed)
        #expect(error("digiwalker-battle:1?s=agumon&t=2&n=a%0Ab") == .malformed)
        #expect(error("digiwalker-battle:1?s=agumon&t=2&n=%E") == .malformed)
        #expect(error("digiwalker-battle:1?s=agumon&t=2&n=%FF%FE") == .malformed) // not UTF-8
    }

    @Test func nameMayDifferFromCatalog() {
        #expect(BattleCard.decode("digiwalker-battle:1?s=agumon&t=2&n=Other%20Name")
            == .success(BattleCard(speciesId: "agumon", name: "Other Name")!))
    }

    @Test func cardsThatCannotBeDecodedCannotBeBuilt() {
        // 32 flags: no forbidden characters and within 32 characters, but the payload would exceed 512 bytes.
        let long = String(repeating: "\u{1F1F0}\u{1F1F7}", count: 32)
        #expect(long.count == 32)
        #expect(!long.unicodeScalars.contains { [.control, .format, .lineSeparator, .paragraphSeparator].contains($0.properties.generalCategory) })
        let payload = "\(BattleCard.prefix)1?s=agumon&t=2&n=" + long.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        #expect(payload.utf8.count > BattleCard.maxPayloadBytes)
        #expect(error(payload) == .tooLong)
        #expect(BattleCard(speciesId: "agumon", name: long) == nil)
        // Whatever can be built round-trips.
        let ok = BattleCard(speciesId: "agumon", name: String(repeating: "\u{1F1F0}\u{1F1F7}", count: 10))
        #expect(ok != nil)
        #expect(ok.map { BattleCard.decode($0.encoded()) == .success($0) } == true)
    }

    @Test func rawNameMustBeAsciiWithValidEscapes() {
        #expect(error("digiwalker-battle:1?s=agumon&t=2&n=아구몬") == .malformed)
        #expect(error("digiwalker-battle:1?s=agumon&t=2&n=a%ZZ") == .malformed)
    }

    @Test func rawNameOnlyAllowsWhatTheEncoderWrites() {
        let base = "digiwalker-battle:1?s=agumon&t=2&n="
        #expect(error(base + "a b") == .malformed)
        #expect(error(base + "a#b") == .malformed)
        #expect(error(base + "a+b") == .malformed)
        #expect(error(base + "a/b") == .malformed)
        #expect(error(base + "a%2") == .malformed)
        #expect(error(base + "a%") == .malformed)
        #expect(error(base + "a%G1") == .malformed)
        #expect(error(base + "A-z_0.9~") == nil)
        #expect(error(base + "a%2fb%2F") == nil)
        // An accepted card encodes again within the limit.
        if case .success(let card) = BattleCard.decode(base + "a%20b") {
            #expect(card.encoded().utf8.count <= BattleCard.maxPayloadBytes)
            #expect(BattleCard.decode(card.encoded()) == .success(card))
        } else { Issue.record("expected success") }
    }

    @Test func invisibleAndBlankNamesAreRejected() {
        let base = "digiwalker-battle:1?s=agumon&t=2&n="
        #expect(error(base + "a%E2%80%8Bb") == .malformed)   // zero width space (Cf)
        #expect(error(base + "a%E2%80%A8b") == .malformed)   // line separator (Zl)
        #expect(error(base + "a%E2%80%A9b") == .malformed)   // paragraph separator (Zp)
        #expect(error(base + "%20%20") == .malformed)         // blank
        #expect(error(base + "%E3%80%80") == .malformed)      // ideographic space only
        #expect(BattleCard.decode(base + "%20a%20") == .success(BattleCard(speciesId: "agumon", name: "a")!))
        #expect(BattleCard(speciesId: "agumon", name: "   ") == nil)
    }

    @Test func stageMustBeDigitsAndUnknownFutureFormatsAreVersions() {
        #expect(error("digiwalker-battle:1?s=agumon&t=%2B2&n=a") == .stageMismatch)
        #expect(error("digiwalker-battle:1?s=agumon&t=+2&n=a") == .stageMismatch)
        #expect(error("digiwalker-battle:1?s=agumon&t=02&n=a") == .stageMismatch)
        #expect(error("digiwalker-battle:2") == .unsupportedVersion(2))
        #expect(error("digiwalker-battle:2/agumon") == .unsupportedVersion(2))
        #expect(error("digiwalker-battle:3:x") == .unsupportedVersion(3))
        #expect(error("digiwalker-battle:1/agumon") == .malformed)
        #expect(error("digiwalker-battle:1") == .malformed)
    }
}
