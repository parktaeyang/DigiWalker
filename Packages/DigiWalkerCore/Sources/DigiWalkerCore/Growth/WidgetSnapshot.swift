import Foundation

/// Small display-only copy of the partner for the watch face complication. The watch app writes it after a
/// settlement; the widget only reads it. It never feeds back into growth rules or the iPhone snapshot.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let supportedSchemaVersions: Set<Int> = [1]
    /// Shared container of the watch app and the widget extension.
    public static let appGroupIdentifier = "group.ty.park.DigiWalker"
    public static let fileName = "widget-snapshot.json"
    public static let widgetKind = "DigiWalkerPartnerWidget"

    public let schemaVersion: Int
    public let monsterId: UUID
    public let speciesId: String
    public let name: String
    public let stage: Int?
    public let isEgg: Bool
    public let totalCreditedSteps: Int
    /// Cumulative steps of the next hatch, evolution or (at the last stage) new egg; nil when the stage is unknown.
    /// A copy written before the new egg rule has nil at the last stage; `remainingSteps` covers that.
    public let nextRequiredSteps: Int?
    public let revision: Int
    public let updatedAt: Date

    public init(state: GameState, now: Date) {
        let monster = state.monster
        schemaVersion = Self.currentSchemaVersion
        monsterId = monster.id
        speciesId = monster.speciesId
        name = monster.name
        stage = monster.stage
        isEgg = monster.isEgg
        totalCreditedSteps = monster.totalCreditedSteps
        if monster.isEgg {
            nextRequiredSteps = Monster.stepsToHatch
        } else if let stage = monster.stage, stage + 1 < EvolutionCard.stageCount {
            nextRequiredSteps = EvolutionCard.requiredSteps(stage: stage + 1)
        } else if monster.stage == EvolutionCard.stageCount - 1 {
            nextRequiredSteps = Monster.stepsForNewEgg
        } else {
            nextRequiredSteps = nil
        }
        revision = state.revision
        updatedAt = now
    }

    /// Steps left until the next hatch, evolution or new egg, never negative. Nil when the stage is unknown.
    public var remainingSteps: Int? {
        if let nextRequiredSteps { return max(0, nextRequiredSteps - totalCreditedSteps) }
        // An older copy has no target at the last stage: work it out from the steps.
        if stage == EvolutionCard.stageCount - 1 { return max(0, Monster.stepsForNewEgg - totalCreditedSteps) }
        return nil
    }

    /// What the complication says about the next step.
    public enum Progress: Equatable, Sendable {
        case hatch(remaining: Int)
        case evolution(remaining: Int)
        /// Last stage, `remaining` steps until a new egg may be started.
        case newEgg(remaining: Int)
        /// Last stage with enough steps to start a new egg.
        case newEggReady
        /// No next stage and not the last one: the stage is unknown, so nothing is claimed.
        case unknown

        /// Same case, ignoring the remaining steps (e.g. counting down to a new egg vs. ready now).
        func sameKind(as other: Self) -> Bool {
            switch (self, other) {
            case (.hatch, .hatch), (.evolution, .evolution), (.newEgg, .newEgg), (.newEggReady, .newEggReady),
                 (.unknown, .unknown): true
            default: false
            }
        }
    }

    public var progress: Progress {
        if isEgg { return .hatch(remaining: remainingSteps ?? 0) }
        guard let remainingSteps else { return .unknown }
        if stage == EvolutionCard.stageCount - 1 {
            return remainingSteps > 0 ? .newEgg(remaining: remainingSteps) : .newEggReady
        }
        return .evolution(remaining: remainingSteps)
    }

    /// True if a widget would draw the same thing: the same look and the same remaining steps. Steps counted
    /// once a new egg is possible show nowhere, so they do not count. Ignores `revision` and `updatedAt`.
    public func sameDisplay(as other: WidgetSnapshot) -> Bool {
        sameLook(as: other) && remainingSteps == other.remainingSteps
    }

    /// True if this identity or look changes (not just the step count).
    public func sameLook(as other: WidgetSnapshot) -> Bool {
        monsterId == other.monsterId && speciesId == other.speciesId && name == other.name
            && stage == other.stage && isEgg == other.isEgg && nextRequiredSteps == other.nextRequiredSteps
            && progress.sameKind(as: other.progress)
    }
}

/// The last snapshot a reload was requested for, and when. Lets a step-only change that was held back
/// be reloaded by a later settlement.
public struct WidgetReloadRecord: Codable, Equatable, Sendable {
    public let snapshot: WidgetSnapshot
    public let at: Date

    public init(snapshot: WidgetSnapshot, at: Date) {
        self.snapshot = snapshot
        self.at = at
    }
}

public enum WidgetReloadPolicy {
    /// A step-only change waits at least this long in the background (reloads in the background use the same
    /// budget as settlements).
    public static let stepOnlyInterval: TimeInterval = 30 * 60

    /// `previous` is what the last reload showed. A new partner, species, stage or name always reloads. A change
    /// in steps alone reloads in the foreground or once `stepOnlyInterval` has passed since the last reload.
    public static func shouldReload(
        previous: WidgetSnapshot?, next: WidgetSnapshot, foreground: Bool, lastReload: Date?, now: Date
    ) -> Bool {
        guard let previous else { return true }
        if next.sameDisplay(as: previous) { return false }
        if !next.sameLook(as: previous) { return true }
        if foreground { return true }
        guard let lastReload else { return true }
        return now.timeIntervalSince(lastReload) >= stepOnlyInterval
    }
}

public enum WidgetTimelineRetry {
    public static let interval: TimeInterval = 20 * 60

    /// When the widget should ask for a new timeline by itself. A readable copy is refreshed by the watch app
    /// (nil, never); an unreadable one is retried later because the app may not be able to push it again soon.
    public static func nextRefresh(copyReadable: Bool, now: Date) -> Date? {
        copyReadable ? nil : now.addingTimeInterval(interval)
    }
}

public enum PixelScaling {
    /// Whole-number factor k >= 1 so that `spritePixels * k` device pixels fit in `availablePoints`.
    /// One image pixel becomes k device pixels. Falls back to 1 for bad input.
    public static func factor(availablePoints: Double, spritePixels: Int, displayScale: Double) -> Int {
        guard availablePoints.isFinite, displayScale.isFinite, availablePoints > 0, displayScale > 0, spritePixels > 0
        else { return 1 }
        let fit = (availablePoints * displayScale / Double(spritePixels)).rounded(.down)
        guard fit >= 1 else { return 1 }
        return Int(min(fit, 64))
    }
}
