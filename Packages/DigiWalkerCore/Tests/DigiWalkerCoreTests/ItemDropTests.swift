import Foundation
import Testing
@testable import DigiWalkerCore

@Suite struct ItemDropTests {
    private func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", n))!
    }

    @Test func catalogHas25UniqueItemsInThreeCategories() {
        let all = ItemCatalog.all
        #expect(all.count == 25)
        #expect(Set(all.map(\.id)).count == 25)
        #expect(Set(all.map(\.name)).count == 25)
        #expect(all.filter { $0.category == .crest }.count == 11)
        #expect(all.filter { $0.category == .digimental }.count == 11)
        #expect(all.filter { $0.category == .other }.map(\.id) == ["x_antibody", "digicore", "digicode"])
        #expect(all.allSatisfy { !$0.name.isEmpty && !$0.japaneseName.isEmpty && !$0.englishName.isEmpty && !$0.source.isEmpty })
        // Official Korean names are not confirmed for any item yet.
        #expect(all.allSatisfy { !$0.nameVerified })
        #expect(ItemCatalog.info(id: "digimental_fate")?.name == "운명의 디지멘탈")
        #expect(ItemCatalog.info(id: "nope") == nil)
    }

    @Test func sameInputGivesSameResultAndFixedValuesNeverChange() {
        let id = UUID(uuidString: "12345678-9ABC-DEF0-1234-56789ABCDEF0")!
        // Pinned so a platform, Swift version or refactor cannot silently change the drops.
        #expect(ItemDrop.seed(monsterId: id, segment: 3) == 16035939015768013351)
        let withPreferred = (1...30).compactMap { s in ItemDrop.roll(monsterId: id, segment: s, preferred: ["digicore"]).map { "\(s):\($0)" } }
        #expect(withPreferred == ["3:crest_knowledge", "9:crest_hope", "13:digicore", "18:crest_friendship",
                                  "27:crest_miracles", "28:crest_light"])
        let without = (1...30).compactMap { s in ItemDrop.roll(monsterId: id, segment: s, preferred: []).map { "\(s):\($0)" } }
        #expect(without == ["3:crest_knowledge", "9:crest_hope", "13:crest_love", "18:crest_friendship",
                            "27:crest_miracles", "28:crest_light"])
        for s in 1...200 {
            #expect(ItemDrop.roll(monsterId: id, segment: s, preferred: ["digicore"])
                == ItemDrop.roll(monsterId: id, segment: s, preferred: ["digicore"]))
        }
    }

    @Test func segmentAndMonsterAreIndependent() {
        let a = (1...400).map { ItemDrop.roll(monsterId: uuid(1), segment: $0, preferred: []) }
        let b = (1...400).map { ItemDrop.roll(monsterId: uuid(2), segment: $0, preferred: []) }
        #expect(a != b)
        #expect(Set((1...400).map { ItemDrop.seed(monsterId: uuid(1), segment: $0) }).count == 400)
    }

    @Test func successRateIsAboutTwentyPercent() {
        let n = 100_000
        var hits = 0
        for i in 0..<n where ItemDrop.roll(monsterId: uuid(i / 50), segment: i % 50 + 1, preferred: []) != nil { hits += 1 }
        let rate = Double(hits) / Double(n)
        #expect(abs(rate - 0.20) < 0.01, "rate \(rate)")
    }

    @Test func preferredItemsTakeHalfOfTheHitsPlusTheirUniformShare() {
        var hits = 0, preferred = 0
        var seen = Set<String>()
        for i in 0..<100_000 {
            guard let item = ItemDrop.roll(monsterId: uuid(i / 50), segment: i % 50 + 1, preferred: ["digicore", "digicode"])
            else { continue }
            hits += 1
            if item == "digicore" || item == "digicode" { preferred += 1 }
            seen.insert(item)
        }
        // 50% from the preferred list (its two ids), 50% uniform over 25 (2/25 of those).
        let share = Double(preferred) / Double(hits)
        #expect(abs(share - (0.5 + 0.5 * 2.0 / 25.0)) < 0.02, "share \(share)")
        #expect(seen.count == 25)
    }

    @Test func emptyPreferredFallsBackToUniform() {
        var counts: [String: Int] = [:]
        var hits = 0
        for i in 0..<100_000 {
            guard let item = ItemDrop.roll(monsterId: uuid(i / 50), segment: i % 50 + 1, preferred: []) else { continue }
            counts[item, default: 0] += 1
            hits += 1
        }
        #expect(counts.count == 25)
        let expected = Double(hits) / 25
        #expect(counts.values.allSatisfy { abs(Double($0) - expected) < expected * 0.2 })
    }

    @Test func segmentForSteps() {
        #expect([0, 4_999, 5_000, 9_999, 10_000, -5].map(ItemDrop.segment(forSteps:)) == [0, 0, 1, 1, 2, 0])
    }
}
