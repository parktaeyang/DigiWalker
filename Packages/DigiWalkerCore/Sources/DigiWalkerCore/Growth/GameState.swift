import Foundation

public enum ExperienceCalculator {
    public static func totalXP(for steps: Int) -> Int { max(0, steps) / 100 * 10 }
    public static func level(for experience: Int) -> Int { max(0, experience) / 250 + 1 }
}

public enum Hatchling: String, CaseIterable, Sendable {
    case botamon, punimon, poyomon

    public var name: String {
        switch self {
        case .botamon: "깜몬"
        case .punimon: "푸니몬"
        case .poyomon: "포요몬"
        }
    }
}

public struct Monster: Codable, Equatable, Sendable {
    public let id: UUID
    public static let eggSpeciesId = "digitama"
    fileprivate static let eggName = "디지타마"
    public static let stepsToHatch = 500
    public var isEgg: Bool { speciesId == Self.eggSpeciesId }
    public var hatchling: Hatchling? { Hatchling(rawValue: speciesId) }
    public fileprivate(set) var speciesId: String
    public fileprivate(set) var name: String
    public fileprivate(set) var experience = 0
    public fileprivate(set) var totalCreditedSteps = 0
    public fileprivate(set) var distanceMeters = 0.0
    public var level: Int { ExperienceCalculator.level(for: experience) }
}

public struct DailyActivityLedger: Codable, Equatable, Sendable {
    public fileprivate(set) var creditedSteps = 0
    public fileprivate(set) var creditedXP = 0
    public fileprivate(set) var creditedDistanceMeters = 0.0
}

public struct GameState: Codable, Equatable, Sendable {
    public private(set) var monster: Monster
    public let createdAt: Date
    public let timeZone: TimeZone
    public private(set) var revision = 0
    public private(set) var enrolledAt: Date?
    public private(set) var lastStepDay: Date?
    public private(set) var ledgers: [Date: DailyActivityLedger] = [:]
    public private(set) var todaySteps: Int?
    public private(set) var observedAt: Date?

    public init(now: Date = .now, timeZone: TimeZone = .current) {
        self.init(speciesId: Monster.eggSpeciesId, name: Monster.eggName, now: now, timeZone: timeZone)
    }

    public init(speciesId: String, name: String, now: Date = .now, timeZone: TimeZone = .current) {
        monster = Monster(id: UUID(), speciesId: speciesId, name: name)
        createdAt = now
        self.timeZone = timeZone
    }

    public var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    public mutating func enroll(at date: Date) {
        if enrolledAt == nil { enrolledAt = date }
    }

    public mutating func settle(day: Date, steps: Int?, distance: Double?) {
        guard let enrolledAt, day >= calendar.startOfDay(for: enrolledAt) else { return }
        let key = calendar.startOfDay(for: day)
        var ledger = ledgers[key] ?? DailyActivityLedger()
        if let steps {
            let high = max(ledger.creditedSteps, steps)
            let xp = ExperienceCalculator.totalXP(for: high)
            monster.experience += xp - ledger.creditedXP
            monster.totalCreditedSteps += high - ledger.creditedSteps
            ledger.creditedSteps = high
            ledger.creditedXP = xp
            lastStepDay = max(key, lastStepDay ?? key)
        }
        if let distance, distance.isFinite, distance > ledger.creditedDistanceMeters {
            monster.distanceMeters += distance - ledger.creditedDistanceMeters
            ledger.creditedDistanceMeters = distance
        }
        if ledger != (ledgers[key] ?? DailyActivityLedger()) {
            ledgers[key] = ledger
            hatchIfReady()
            revision += 1
        }
    }

    // Upgrade the original built-in starter in place so phone caches keep the same partner ID.
    public mutating func migrateLegacyStarter() {
        guard monster.speciesId == "starter_acorn", monster.name == "도토롱" else { return }
        monster.speciesId = Monster.eggSpeciesId
        monster.name = Monster.eggName
        hatchIfReady()
        revision += 1
    }

    private mutating func hatchIfReady() {
        guard monster.isEgg, monster.totalCreditedSteps >= Monster.stepsToHatch,
              let baby = Hatchling.allCases.randomElement() else { return }
        monster.speciesId = baby.rawValue
        monster.name = baby.name
    }

    public mutating func recordObservation(steps: Int?, at date: Date) {
        if steps != todaySteps || observedAt.map({ !calendar.isDate($0, inSameDayAs: date) }) != false {
            todaySteps = steps
            observedAt = date
            revision += 1
        }
    }

    public var snapshot: MonsterSnapshot {
        MonsterSnapshot(schemaVersion: 1, revision: revision, createdAt: createdAt,
                        monster: monster, todaySteps: todaySteps, observedAt: observedAt, timeZone: timeZone)
    }
}

public struct MonsterSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let revision: Int
    public let createdAt: Date
    public let monster: Monster
    public let todaySteps: Int?
    public let observedAt: Date?
    public let timeZone: TimeZone?

    public func supersedes(_ cached: Self?) -> Bool {
        guard schemaVersion == 1, revision >= 0, monster.experience >= 0,
              monster.totalCreditedSteps >= 0, monster.distanceMeters >= 0,
              (todaySteps ?? 0) >= 0, !monster.name.isEmpty, !monster.speciesId.isEmpty else { return false }
        guard let cached else { return true }
        if monster.id == cached.monster.id { return revision > cached.revision }
        return createdAt > cached.createdAt
    }
}
