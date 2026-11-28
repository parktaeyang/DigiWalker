import Foundation

public enum BattleAction: Equatable, Sendable { case attack, defend }

public struct BattleMove: Equatable, Sendable {
    public static let valueRange = 0...100
    public let action: BattleAction
    /// Always within `valueRange`: the init clamps out-of-range input (by design, not an error).
    public let value: Int

    public init(_ action: BattleAction, _ value: Int) {
        self.action = action
        self.value = min(max(value, Self.valueRange.lowerBound), Self.valueRange.upperBound)
    }
}

/// Outcome from the point of view of the user on this device (the one who scanned the QR).
public enum RoundOutcome: Equatable, Sendable { case win, lose, draw }

public enum RoundNote: Equatable, Sendable {
    /// Attack against attack.
    case clash
    /// Defend against defend (always a draw).
    case guardDraw
    /// An attack beat a defense (or tied against it with my attack).
    case critical
    /// A defense beat an attack (or tied against it with my defense).
    case counter
}

public enum BattleRules {
    public static let patternLength = 3
    public static let winsNeeded = 2

    /// Judges one round. Ties go to `mine` (the side that scanned the QR).
    public static func judge(mine: BattleMove, theirs: BattleMove) -> (outcome: RoundOutcome, note: RoundNote) {
        switch (mine.action, theirs.action) {
        case (.defend, .defend):
            return (.draw, .guardDraw)
        case (.attack, .attack):
            return (mine.value >= theirs.value ? .win : .lose, .clash)
        case (.attack, .defend):
            if mine.value == theirs.value { return (.win, .critical) }
            return mine.value > theirs.value ? (.win, .critical) : (.lose, .counter)
        case (.defend, .attack):
            if mine.value == theirs.value { return (.win, .counter) }
            return mine.value > theirs.value ? (.win, .counter) : (.lose, .critical)
        }
    }

    public static func randomValue(using rng: inout some RandomNumberGenerator) -> Int {
        Int.random(in: BattleMove.valueRange, using: &rng)
    }

    public static func randomMove(using rng: inout some RandomNumberGenerator) -> BattleMove {
        let action: BattleAction = Bool.random(using: &rng) ? .attack : .defend
        return BattleMove(action, randomValue(using: &rng))
    }

    public static func randomPattern(using rng: inout some RandomNumberGenerator) -> [BattleMove] {
        (0..<patternLength).map { _ in randomMove(using: &rng) }
    }
}

public enum BattleWinner: Equatable, Sendable { case me, opponent }

/// One best-of-until-two-wins battle seen from this device. Plain value; nothing is saved.
public struct BattleSession: Equatable, Sendable {
    public struct Round: Equatable, Sendable {
        /// 0-based.
        public let index: Int
        public let mine: BattleMove
        public let theirs: BattleMove
        public let outcome: RoundOutcome
        public let note: RoundNote
    }

    public let opponent: [BattleMove]
    public private(set) var rounds: [Round] = []

    /// Nil unless the pattern has exactly `BattleRules.patternLength` moves.
    public init?(opponent: [BattleMove]) {
        guard opponent.count == BattleRules.patternLength else { return nil }
        self.opponent = opponent
    }

    public init(using rng: inout some RandomNumberGenerator) {
        opponent = BattleRules.randomPattern(using: &rng)
    }

    public var myWins: Int { rounds.filter { $0.outcome == .win }.count }
    public var theirWins: Int { rounds.filter { $0.outcome == .lose }.count }
    public var isFinished: Bool { myWins >= BattleRules.winsNeeded || theirWins >= BattleRules.winsNeeded }
    public var winner: BattleWinner? {
        guard isFinished else { return nil }
        return myWins >= BattleRules.winsNeeded ? .me : .opponent
    }
    /// Three rounds are done and nobody has two wins: more rounds are needed.
    public var isAwaitingExtraRound: Bool { rounds.count >= BattleRules.patternLength && !isFinished }
    /// The opponent move for the next round; the pattern restarts after every three rounds.
    public var nextOpponentMove: BattleMove { opponent[rounds.count % BattleRules.patternLength] }

    /// Plays one round. Returns false and changes nothing once the battle is finished.
    @discardableResult
    public mutating func play(_ move: BattleMove) -> Bool {
        guard !isFinished else { return false }
        let theirs = nextOpponentMove
        let result = BattleRules.judge(mine: move, theirs: theirs)
        rounds.append(Round(index: rounds.count, mine: move, theirs: theirs, outcome: result.outcome, note: result.note))
        return true
    }

    /// Picking an action fixes its value at that moment (0...100 from `rng`).
    @discardableResult
    public mutating func play(_ action: BattleAction, using rng: inout some RandomNumberGenerator) -> Bool {
        guard !isFinished else { return false }
        return play(BattleMove(action, BattleRules.randomValue(using: &rng)))
    }
}
