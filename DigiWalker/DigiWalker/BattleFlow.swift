import DigiWalkerCore
import Foundation
import Observation

/// Lets a flow own a replaceable `any RandomNumberGenerator` and still pass it as `inout some RandomNumberGenerator`.
struct BoxedGenerator: RandomNumberGenerator {
    var base: any RandomNumberGenerator
    mutating func next() -> UInt64 { base.next() }
}

/// Everything the battle screens decide, kept out of the views: scan handling, matching, and the battle itself.
/// Nothing here is saved or sent; the snapshot is only read.
@MainActor @Observable
final class BattleFlow {
    struct Encounter: Equatable {
        let mine: BattleFighter
        let opponent: BattleCard
        /// Judged rounds. Stays empty until the first three picks are in.
        var session: BattleSession
        /// My first three picks, values drawn the moment each was chosen. Nothing is judged before all three exist.
        var picks: [BattleMove] = []

        /// Still collecting the first three picks (no result may show).
        var isCollecting: Bool { picks.count < BattleRules.patternLength }
        var isFinished: Bool { !isCollecting && session.isFinished }
        var isAwaitingExtraRound: Bool { !isCollecting && session.isAwaitingExtraRound }
        /// Picks made after the battle was already decided (e.g. a 3rd pick after 2:0): shown, never judged.
        var undecidedPicks: [(index: Int, move: BattleMove)] {
            guard isFinished else { return [] }
            return picks.enumerated().filter { $0.offset >= session.rounds.count }.map { ($0.offset, $0.element) }
        }
    }

    struct PendingPick: Identifiable, Equatable {
        let opponent: BattleCard
        let stage: Int
        let candidates: [BattleFighter]
        var id: String { opponent.encoded() }
    }

    static let eggMessage = "부화한 뒤에 배틀할 수 있어요"
    static let noFightersMessage = "부화한 디지몬이 있어야 배틀할 수 있어요"
    static let noSameStageMessage = "같은 단계의 디지몬이 없어요"
    static let opponentMustLowerMessage = "상대가 같은 단계의 디지몬으로 QR을 다시 만들어야 해요"

    private(set) var roster: BattleRoster
    private(set) var myFighter: BattleFighter?
    /// True once the user picked a fighter; until then `myFighter` follows the current partner.
    private(set) var isFighterChosenByUser = false
    /// The last problem or hint to show on the battle screen.
    var notice: String?
    var pendingPick: PendingPick?
    var encounter: Encounter?
    @ObservationIgnored private var rng: BoxedGenerator

    init(snapshot: MonsterSnapshot, rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        let roster = BattleRoster(snapshot: snapshot)
        self.roster = roster
        myFighter = roster.defaultFighter
        self.rng = BoxedGenerator(base: rng)
    }

    /// Set when the whole screen is unavailable: the current partner is an egg, or nobody has hatched.
    var blockedMessage: String? {
        if roster.isBlockedByEgg { return Self.eggMessage }
        return roster.stages.isEmpty ? Self.noFightersMessage : nil
    }

    /// A newer cache arrived: recompute who can fight. A battle already started is left alone.
    func update(snapshot: MonsterSnapshot) {
        roster = BattleRoster(snapshot: snapshot)
        if isFighterChosenByUser, let chosen = myFighter, roster.contains(chosen) {
            // Kept as chosen.
        } else {
            myFighter = roster.defaultFighter
            isFighterChosenByUser = false
        }
        if blockedMessage != nil || pendingPick?.candidates.allSatisfy(roster.contains) == false { pendingPick = nil }
    }

    var myCard: BattleCard? {
        guard blockedMessage == nil, let f = myFighter else { return nil }
        return BattleCard(speciesId: f.speciesId, name: f.name)
    }

    func select(_ fighter: BattleFighter) {
        if roster.contains(fighter) {
            myFighter = fighter
            isFighterChosenByUser = true
        }
    }

    /// Scan result (or pasted text in debug builds).
    func handleScanned(_ text: String) {
        notice = nil
        pendingPick = nil
        if let blocked = blockedMessage { notice = blocked; return }
        switch BattleCard.decode(text) {
        case .failure(let error):
            notice = Self.message(for: error)
        case .success(let card):
            switch BattleMatch.match(mine: myFighter, opponent: card, roster: roster) {
            case .eggBlocked: notice = Self.eggMessage
            case .ready(let mine): startBattle(mine: mine, opponent: card)
            case .pick(let stage, let candidates): pendingPick = PendingPick(opponent: card, stage: stage, candidates: candidates)
            case .noSameStage: notice = Self.noSameStageMessage
            case .opponentMustLower: notice = Self.opponentMustLowerMessage
            }
        }
    }

    /// Fights with `mine` for this battle only; the "my fighter" shown on the screen stays as it is.
    func startBattle(mine: BattleFighter, opponent: BattleCard) {
        pendingPick = nil
        encounter = Encounter(mine: mine, opponent: opponent, session: BattleSession(using: &rng))
    }

    func choose(_ action: BattleAction) {
        guard var e = encounter, !e.isFinished else { return }
        if e.isCollecting {
            e.picks.append(BattleMove(action, BattleRules.randomValue(using: &rng)))
            if !e.isCollecting { for move in e.picks { e.session.play(move) } }
        } else {
            e.session.play(action, using: &rng)
        }
        encounter = e
    }

    /// Same fighters, new opponent pattern.
    func rematch() {
        guard let e = encounter else { return }
        // Blocked (egg) or the fighter is gone: back to the lobby instead of a new battle.
        guard blockedMessage == nil, roster.contains(e.mine) else { encounter = nil; return }
        startBattle(mine: e.mine, opponent: e.opponent)
    }

    static func message(for error: BattleCardError) -> String {
        switch error {
        case .tooLong, .notBattleCode, .malformed: "DigiWalker 배틀 QR이 아니에요"
        case .unsupportedVersion: "앱 버전이 달라요. 두 기기 모두 앱을 최신으로 설치해 주세요"
        case .unknownSpecies: "이 기기에서 모르는 디지몬이에요. 앱을 최신으로 설치해 주세요"
        case .egg: "알은 배틀할 수 없어요"
        case .stageMismatch, .notEligible: "배틀할 수 없는 디지몬 정보예요"
        }
    }

    // MARK: Result text

    static func actionName(_ action: BattleAction) -> String { action == .attack ? "공격" : "방어" }

    /// "1판 크리티컬! 승" / "2판 무승부" / "3판 반격… 패".
    static func summary(_ round: BattleSession.Round) -> String {
        let n = "\(round.index + 1)판"
        switch round.outcome {
        case .draw: return "\(n) 무승부"
        case .win:
            switch round.note {
            case .critical: return "\(n) 크리티컬! 승"
            case .counter: return "\(n) 반격! 승"
            default: return "\(n) 승"
            }
        case .lose:
            switch round.note {
            case .critical: return "\(n) 크리티컬… 패"
            case .counter: return "\(n) 반격… 패"
            default: return "\(n) 패"
            }
        }
    }

    /// "3판 — (승부 결정 후)" for a pick that was never judged.
    static func undecidedSummary(index: Int) -> String { "\(index + 1)판 — (승부 결정 후)" }

    /// "나 공격 32".
    static func undecidedDetail(_ move: BattleMove) -> String { "나 \(actionName(move.action)) \(move.value)" }

    /// "나 공격 32 · 상대 방어 55".
    static func detail(_ round: BattleSession.Round) -> String {
        "나 \(actionName(round.mine.action)) \(round.mine.value) · 상대 \(actionName(round.theirs.action)) \(round.theirs.value)"
    }

    /// "1승 1패 1무".
    static func score(_ session: BattleSession) -> String {
        let draws = session.rounds.filter { $0.outcome == .draw }.count
        return "\(session.myWins)승 \(session.theirWins)패 \(draws)무"
    }
}
