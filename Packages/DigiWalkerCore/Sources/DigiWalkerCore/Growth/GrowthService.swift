import Foundation

public enum ActivityMetric: Sendable {
    case steps, distanceMeters
}

public enum GrowthService {
    /// A single cutoff keeps every query in the same settlement, including a refresh across midnight.
    @MainActor
    public static func reconcile(_ saved: GameState, through now: Date,
        read: (ActivityMetric, Date, Date) async throws -> Double?) async throws -> GameState {
        guard let enrolled = saved.enrolledAt, now >= enrolled else { return saved }
        let calendar = saved.calendar
        let today = calendar.startOfDay(for: now)
        let firstDay = calendar.startOfDay(for: enrolled)
        let previous = saved.lastStepDay.flatMap { calendar.date(byAdding: .day, value: -1, to: $0) }
        var day = max(firstDay, previous ?? firstDay)
        var candidate = saved
        var todayCount: Int?
        while day <= today {
            try Task.checkCancellation()
            guard let next = calendar.dateInterval(of: .day, for: day)?.end else {
                throw CocoaError(.formatting)
            }
            let start = max(enrolled, day)
            let end = min(next, now)
            let steps = try await read(.steps, start, end).map(Int.init)
            let meters = try await read(.distanceMeters, start, end)
            candidate.settle(day: day, steps: steps, distance: meters)
            if day == today {
                if start == today {
                    todayCount = steps
                } else {
                    todayCount = try await read(.steps, today, now).map(Int.init)
                }
            }
            day = next
        }
        candidate.recordObservation(steps: todayCount, at: now)
        return candidate
    }
}
