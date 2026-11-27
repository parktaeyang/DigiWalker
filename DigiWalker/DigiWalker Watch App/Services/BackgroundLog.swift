import DigiWalkerCore
import Foundation

/// What woke the app in the background. Foreground activations and HealthKit callbacks that arrive while the app
/// is open are not wake-ups for this log.
enum WakeSource: String, Codable, Equatable {
    case refresh
    case healthKit

    var label: String {
        switch self {
        case .refresh: "앱 새로고침"
        case .healthKit: "HealthKit"
        }
    }
}

/// How a background run ended. `arrived` stays if the run was cut off (timeout, expiration, process stop).
enum SettlementOutcome: String, Codable, Equatable {
    case arrived
    case unchanged
    case settled
    case growth
    case notEnrolled
    case failed

    var label: String {
        switch self {
        case .arrived: "도착 (결과 없음)"
        case .unchanged: "변경 없음"
        case .settled: "정산 반영"
        case .growth: "부화·진화·아이템·새 알"
        case .notEnrolled: "미연결"
        case .failed: "실패"
        }
    }
}

struct BackgroundLogEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let at: Date
    let source: WakeSource
    var outcome: SettlementOutcome

    init(id: UUID = UUID(), at: Date, source: WakeSource, outcome: SettlementOutcome = .arrived) {
        self.id = id
        self.at = at
        self.source = source
        self.outcome = outcome
    }
}

/// The diagnostic log: the newest 20 wake-ups plus per-day counts and the last wake time, which do not depend
/// on the ring so "today N times" is not capped at 20.
struct BackgroundLogData: Codable, Equatable {
    static let capacity = 20
    /// Days of counts to keep.
    static let keptDays = 7

    var entries: [BackgroundLogEntry] = []
    var dayCounts: [String: Int] = [:]
    var lastAt: Date?
    var lastSource: WakeSource?

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Records a wake-up the moment it arrives.
    func arriving(_ entry: BackgroundLogEntry, calendar: Calendar = .current) -> BackgroundLogData {
        var next = self
        next.entries = Array((entries + [entry]).suffix(Self.capacity))
        next.dayCounts[Self.dayKey(entry.at, calendar: calendar), default: 0] += 1
        next.dropOldDays()
        if lastAt.map({ entry.at >= $0 }) ?? true {
            next.lastAt = entry.at
            next.lastSource = entry.source
        }
        return next
    }

    private mutating func dropOldDays() {
        if dayCounts.count > Self.keptDays {
            for key in dayCounts.keys.sorted().dropLast(Self.keptDays) { dayCounts[key] = nil }
        }
    }

    /// Writes the result of a run recorded earlier. Nothing happens if the entry already left the ring.
    func finishing(id: UUID, outcome: SettlementOutcome) -> BackgroundLogData {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return self }
        var next = self
        next.entries[index].outcome = outcome
        return next
    }

    /// Adds runs recorded in memory while this file could not be read. The ring takes the entries that are not in
    /// it yet; the day counts and last time are merged on their own, so they do not depend on the ring (25 runs
    /// stay 25 even though the ring holds 20).
    func merging(unsaved: BackgroundLogData, calendar: Calendar = .current) -> BackgroundLogData {
        var next = self
        let added = unsaved.entries.filter { entry in !entries.contains { $0.id == entry.id } }
        next.entries = Array((entries + added).suffix(Self.capacity))
        for (day, count) in unsaved.dayCounts { next.dayCounts[day, default: 0] += count }
        next.dropOldDays()
        if let at = unsaved.lastAt, lastAt.map({ at >= $0 }) ?? true {
            next.lastAt = at
            next.lastSource = unsaved.lastSource
        }
        return next
    }

    func todayCount(now: Date, calendar: Calendar = .current) -> Int {
        dayCounts[Self.dayKey(now, calendar: calendar)] ?? 0
    }

    /// One line for the bottom of the home screen.
    func summary(now: Date, calendar: Calendar = .current) -> String {
        guard let lastAt, let lastSource else { return "백그라운드 실행 기록 없음" }
        let time = lastAt.formatted(.dateTime.hour().minute())
        return "백그라운드 마지막 \(time) \(lastSource.label) · 오늘 \(todayCount(now: now, calendar: calendar))회"
    }
}

/// Diagnostic log of wake-ups, kept in its own small file apart from the game state.
protocol BackgroundLogging {
    /// A missing file is empty data; an unreadable one throws.
    func load() throws -> BackgroundLogData
    func save(_ data: BackgroundLogData) throws
}

struct BackgroundLogFile: BackgroundLogging {
    private let file: StateFile<BackgroundLogData>

    init(url: URL = URL.applicationSupportDirectory.appending(path: "background-log.json")) {
        file = StateFile(url: url)
    }

    func load() throws -> BackgroundLogData { try file.load() ?? BackgroundLogData() }
    func save(_ data: BackgroundLogData) throws { try file.save(data) }
}

final class MemoryBackgroundLog: BackgroundLogging {
    private var data = BackgroundLogData()
    func load() throws -> BackgroundLogData { data }
    func save(_ data: BackgroundLogData) throws { self.data = data }
}
