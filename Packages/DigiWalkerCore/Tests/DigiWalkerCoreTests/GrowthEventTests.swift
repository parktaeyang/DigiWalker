import Foundation
import Testing
@testable import DigiWalkerCore

@Suite struct GrowthEventTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func enrolled() -> GameState {
        var state = GameState(now: start, timeZone: .gmt)
        state.enroll(at: start)
        return state
    }

    private func settled(_ state: GameState, steps: Int, seed: UInt64 = 7) -> GameState {
        var next = state
        var generator = SeededGenerator(seed: seed)
        next.settle(day: start, steps: steps, distance: nil, at: nil, using: &generator)
        return next
    }

    @Test func eventSurvivesEncodingForTheUndeliveredQueue() throws {
        let before = enrolled()
        let after = settled(before, steps: 15_000)
        let event = try #require(GrowthEvent.between(before, after))
        let decoded = try JSONDecoder().decode([GrowthEvent].self, from: JSONEncoder().encode([event]))
        #expect(decoded == [event])
        #expect(decoded.first?.title == event.title)
    }

    @Test func hatchAt500() throws {
        let before = settled(enrolled(), steps: 499)
        let after = settled(before, steps: 500)
        let event = try #require(GrowthEvent.between(before, after))
        #expect(event.kind == .hatched)
        #expect(event.fromSpeciesId == "digitama")
        #expect(event.toSpeciesId == after.monster.speciesId)
        #expect(event.intermediateSpeciesIds.isEmpty)
        #expect(event.title == "디지타마가 부화했어요!")
        #expect(event.body == "새 파트너 · \(after.monster.name)")
        #expect(GrowthEvent.between(before, before) == nil)
    }

    @Test func evolvesOneStageAtFirstThreshold() throws {
        let before = settled(enrolled(), steps: 500)
        let after = settled(before, steps: EvolutionCard.requiredSteps(stage: 1))
        let event = try #require(GrowthEvent.between(before, after))
        #expect(event.kind == .evolved)
        #expect(event.fromSpeciesId == before.monster.speciesId)
        #expect(event.toSpeciesId == after.monster.speciesId)
        #expect(event.intermediateSpeciesIds.isEmpty)
        #expect(event.evolutionSteps == 1)
        let from = before.monster.name, to = after.monster.name
        #expect(event.title == "\(from)\(KoreanParticle.subject(from)) \(to)\(KoreanParticle.direction(to)) 진화했어요!")
        #expect(event.body == "새 모습 · \(to)")
    }

    @Test func hatchAndTwoStagesInOneSettlement() throws {
        let before = enrolled()
        let after = settled(before, steps: 15_000) // stage 2
        #expect(after.monster.stage == 2)
        let event = try #require(GrowthEvent.between(before, after))
        #expect(event.kind == .hatched)
        #expect(event.intermediateSpeciesIds.count == 2)
        #expect(event.evolutionSteps == 2)
        #expect(event.intermediateSpeciesIds == Array(after.dex.map(\.speciesId).dropFirst().dropLast()))
        #expect(event.title == "디지타마가 부화했어요!")
        #expect(event.body.contains("2단계 진화해"))
    }

    @Test func evolvesAcrossOneIntermediateSpecies() throws {
        let before = settled(enrolled(), steps: 500)
        let after = settled(before, steps: 15_000)
        let event = try #require(GrowthEvent.between(before, after))
        #expect(event.kind == .evolved)
        #expect(event.intermediateSpeciesIds.count == 1)
        #expect(event.title.contains("거쳐"))
    }

    @Test func noEventForSameReadingDecreaseOrStepsOnly() {
        let before = settled(enrolled(), steps: 600)
        #expect(GrowthEvent.between(before, settled(before, steps: 600)) == nil)
        let decreased = settled(before, steps: 550)
        #expect(decreased == before)
        #expect(GrowthEvent.between(before, decreased) == nil)
        let more = settled(before, steps: 900)
        #expect(more.revision > before.revision)
        #expect(GrowthEvent.between(before, more) == nil)
    }

    @Test func noEventForDifferentGeneration() {
        let a = settled(enrolled(), steps: 600)
        let b = settled(enrolled(), steps: 10_000)
        #expect(a.monster.id != b.monster.id)
        #expect(GrowthEvent.between(a, b) == nil)
    }

    @Test func particles() {
        #expect(KoreanParticle.subject("깜몬") == "이")
        #expect(KoreanParticle.subject("코로모") == "가")
        #expect(KoreanParticle.subject("Agumon") == "이(가)")
        #expect(KoreanParticle.object("깜몬") == "을")
        #expect(KoreanParticle.object("코로모") == "를")
        #expect(KoreanParticle.direction("코로모") == "로")
        #expect(KoreanParticle.direction("깜몬") == "으로")
        #expect(KoreanParticle.direction("아구몰") == "로")
        #expect(KoreanParticle.direction("Agumon") == "(으)로")
    }
}
