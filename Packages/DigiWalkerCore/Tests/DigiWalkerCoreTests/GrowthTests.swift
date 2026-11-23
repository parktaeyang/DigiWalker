import Foundation
import Testing
@testable import DigiWalkerCore

@Suite struct GrowthTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func newState(at date: Date? = nil) -> GameState {
        GameState(speciesId: "starter_acorn", name: "도토롱", now: date ?? start, timeZone: .gmt)
    }

    @Test func rewardsByDailyTotalAndKeepsHighWaterMark() {
        var game = newState()
        game.enroll(at: start)
        for (steps, expectedXP) in [(99, 0), (150, 10), (200, 20), (1000, 100),
                                    (2500, 250), (2500, 250), (2200, 250), (3000, 300)] {
            game.settle(day: start, steps: steps, distance: nil)
            #expect(game.monster.experience == expectedXP)
        }
        #expect(game.monster.level == 2)
        #expect(game.monster.totalCreditedSteps == 3000)
        game.settle(day: start, steps: nil, distance: 2000)
        game.settle(day: start, steps: nil, distance: 1000)
        #expect(game.monster.distanceMeters == 2000)
        #expect(game.monster.experience == 300)
    }

    @Test func enrollmentAndNewDayHaveIndependentThresholds() {
        var game = newState()
        game.settle(day: start, steps: 5000, distance: 500)
        #expect(game.monster.totalCreditedSteps == 0)
        game.enroll(at: start)
        game.enroll(at: start.addingTimeInterval(600))
        #expect(game.enrolledAt == start)
        game.settle(day: start.addingTimeInterval(-86400), steps: 1000, distance: nil)
        game.settle(day: start, steps: 150, distance: nil)
        let tomorrow = start.addingTimeInterval(86400)
        game.settle(day: tomorrow, steps: 50, distance: nil)
        #expect(game.monster.experience == 10)
        game.settle(day: tomorrow, steps: 100, distance: nil)
        #expect(game.monster.experience == 20)
        #expect(game.ledgers.count == 2)
    }

    @Test func restoreAndReplayAreIdempotent() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = StateFile<GameState>(url: directory.appending(path: "state.json"))
        #expect(try file.load() == nil)
        var game = newState()
        game.enroll(at: start)
        game.settle(day: start, steps: 2500, distance: 750)
        game.recordObservation(steps: 4600, at: start)
        try file.save(game)
        var restored = try #require(try file.load())
        restored.settle(day: start, steps: 2500, distance: 750)
        restored.recordObservation(steps: 4600, at: start.addingTimeInterval(5))
        #expect(restored.snapshot == game.snapshot)
        #expect(restored.ledgers == game.ledgers)
        try Data("broken".utf8).write(to: file.url)
        #expect(throws: DecodingError.self) { try file.load() }
    }

    @Test func ignoreStaleDuplicateAndSupersededGeneration() throws {
        var game = newState()
        let first = game.snapshot
        game.recordObservation(steps: 100, at: start)
        let second = game.snapshot
        #expect(first.supersedes(nil))
        #expect(second.supersedes(first))
        #expect(!second.supersedes(second))
        #expect(!first.supersedes(second))
        let replacement = newState(at: start.addingTimeInterval(10)).snapshot
        #expect(replacement.supersedes(second))
        #expect(!second.supersedes(replacement))
        let unknownVersion = MonsterSnapshot(schemaVersion: 2, revision: 5, createdAt: start,
            monster: game.monster, todaySteps: nil, observedAt: nil, timeZone: .gmt)
        #expect(!unknownVersion.supersedes(nil))
    }
}

extension GrowthTests {
    @MainActor @Test func onboardingDisplaysWholeDayAndOnlyRewardsAfterEnrollment() async throws {
        var game = newState()
        game.enroll(at: start)
        let now = start.addingTimeInterval(600)
        let result = try await GrowthService.reconcile(game, through: now) { metric, from, to in
            #expect(to == now)
            if metric == .distanceMeters { return nil }
            return from == start ? 150 : 2150
        }
        #expect(result.todaySteps == 2150)
        #expect(result.monster.experience == 10)
        #expect(result.monster.totalCreditedSteps == 150)
    }

    @MainActor @Test func catchUpAcrossDSTAndKeepDaysDisjoint() async throws {
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        let start = try Date("2026-03-07T20:00:00Z", strategy: .iso8601)
        let end = try Date("2026-03-09T10:00:00Z", strategy: .iso8601)
        var game = GameState(speciesId: "starter_acorn", name: "도토롱", now: start, timeZone: zone)
        game.enroll(at: start)
        var intervals: [DateInterval] = []
        let result = try await GrowthService.reconcile(game, through: end) { metric, from, to in
            guard metric == .steps else { return nil }
            intervals.append(DateInterval(start: from, end: to))
            return 100
        }
        #expect(intervals.count == 3)
        #expect(intervals.first?.start == start)
        #expect(intervals.last?.end == end)
        #expect(intervals[0].end == intervals[1].start)
        #expect(intervals[1].duration == 23 * 3600)
        #expect(intervals[1].end == intervals[2].start)
        #expect(result.monster.experience == 30)
        #expect(result.todaySteps == 100)
    }
}
