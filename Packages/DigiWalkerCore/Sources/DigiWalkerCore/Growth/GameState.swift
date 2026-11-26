import Foundation

public enum ExperienceCalculator {
    public static func totalXP(for steps: Int) -> Int { max(0, steps) / 100 * 10 }
    public static func level(for experience: Int) -> Int { max(0, experience) / 250 + 1 }
}

public struct Monster: Codable, Equatable, Sendable {
    public let id: UUID
    public static let eggSpeciesId = SpeciesCatalog.eggId
    fileprivate static let eggName = "디지타마"
    public static let stepsToHatch = EvolutionCard.requiredSteps(stage: 0)
    public var isEgg: Bool { speciesId == Self.eggSpeciesId }
    public fileprivate(set) var speciesId: String
    public fileprivate(set) var name: String
    public fileprivate(set) var experience = 0
    public fileprivate(set) var totalCreditedSteps = 0
    public fileprivate(set) var distanceMeters = 0.0
    /// Evolution card fixed at hatching. Nil for eggs and for states saved before cards existed.
    public fileprivate(set) var cardId: String?
    public var level: Int { ExperienceCalculator.level(for: experience) }
    public var species: SpeciesInfo? { SpeciesCatalog.info(id: speciesId) }
    public var card: EvolutionCard? { cardId.flatMap(SpeciesCatalog.card(id:)) }
    /// Stage 0...5 within the card; nil for eggs, legacy or unknown species.
    public var stage: Int? { card?.stage(of: speciesId) }

    fileprivate init(id: UUID, speciesId: String, name: String) {
        self.id = id
        self.speciesId = speciesId
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case id, speciesId, name, experience, totalCreditedSteps, distanceMeters, cardId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        speciesId = try c.decode(String.self, forKey: .speciesId)
        name = try c.decode(String.self, forKey: .name)
        experience = try c.decode(Int.self, forKey: .experience)
        totalCreditedSteps = try c.decode(Int.self, forKey: .totalCreditedSteps)
        distanceMeters = try c.decode(Double.self, forKey: .distanceMeters)
        cardId = try c.decodeIfPresent(String.self, forKey: .cardId)
        // A card must be a known card, and a known species must belong to it. Unknown species stay readable.
        if let cardId {
            guard let card = SpeciesCatalog.card(id: cardId) else {
                throw DecodingError.dataCorruptedError(forKey: .cardId, in: c, debugDescription: "unknown card \(cardId)")
            }
            if SpeciesCatalog.info(id: speciesId) != nil, card.stage(of: speciesId) == nil {
                throw DecodingError.dataCorruptedError(forKey: .cardId, in: c,
                    debugDescription: "species \(speciesId) is not on card \(cardId)")
            }
        }
    }
}

/// A species the partner has been (first time only). `firstMetAt` is the settlement time that confirmed it.
public struct DexEntry: Codable, Equatable, Sendable {
    public let speciesId: String
    public let firstMetAt: Date
    public let firstMetSteps: Int
    public let cardId: String?
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
    /// Species met by this partner generation, in the order they were met. Never contains duplicates.
    public private(set) var dex: [DexEntry] = []
    /// Items received so far, oldest first. Belongs to the whole game, so it stays for the next partner.
    /// Duplicates are allowed (a count), but `(monsterId, segment)` is unique. Items are never consumed.
    public private(set) var items: [ItemGrant] = []
    /// Last 5,000-step segment of the current partner whose drop was already rolled (win or lose).
    public private(set) var itemSegmentsRolled = 0

    public init(now: Date = .now, timeZone: TimeZone = .current) {
        self.init(speciesId: Monster.eggSpeciesId, name: Monster.eggName, now: now, timeZone: timeZone)
    }

    /// `monsterId` is only chosen by tests (item drops depend on it); the app always lets it be random.
    init(speciesId: String, name: String, now: Date = .now, timeZone: TimeZone = .current, monsterId: UUID = UUID()) {
        monster = Monster(id: monsterId, speciesId: speciesId, name: name)
        createdAt = now
        self.timeZone = timeZone
        if monster.isEgg { recordDex(speciesId: speciesId, steps: 0, at: now, cardId: nil) }
    }

    private enum CodingKeys: String, CodingKey {
        case monster, createdAt, timeZone, revision, enrolledAt, lastStepDay, ledgers, todaySteps, observedAt, dex
        case items, itemSegmentsRolled
    }

    // Files written before evolution cards existed have no `dex` key; keep them readable.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        monster = try c.decode(Monster.self, forKey: .monster)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        timeZone = try c.decode(TimeZone.self, forKey: .timeZone)
        revision = try c.decode(Int.self, forKey: .revision)
        enrolledAt = try c.decodeIfPresent(Date.self, forKey: .enrolledAt)
        lastStepDay = try c.decodeIfPresent(Date.self, forKey: .lastStepDay)
        ledgers = try c.decode([Date: DailyActivityLedger].self, forKey: .ledgers)
        todaySteps = try c.decodeIfPresent(Int.self, forKey: .todaySteps)
        observedAt = try c.decodeIfPresent(Date.self, forKey: .observedAt)
        let decodedDex = try c.decodeIfPresent([DexEntry].self, forKey: .dex)
        // Only files from before cards existed lack `dex`. A card without a dex is a damaged save.
        if monster.cardId != nil, decodedDex?.isEmpty ?? true {
            throw DecodingError.dataCorruptedError(forKey: .dex, in: c,
                debugDescription: "monster has cardId but dex is missing or empty")
        }
        // A modern save (has `dex`) of a card-line species past stage 0 must name its card.
        if decodedDex != nil, monster.cardId == nil,
           SpeciesCatalog.cards.contains(where: { ($0.stage(of: monster.speciesId) ?? 0) >= 1 }) {
            throw DecodingError.dataCorruptedError(forKey: .monster, in: c,
                debugDescription: "monster \(monster.speciesId) has a dex but no cardId")
        }
        var seen = Set<String>()
        if let decodedDex, !decodedDex.allSatisfy({ !$0.speciesId.isEmpty && $0.firstMetSteps >= 0 && seen.insert($0.speciesId).inserted }) {
            throw DecodingError.dataCorruptedError(forKey: .dex, in: c,
                debugDescription: "dex has an empty or duplicate speciesId or negative steps")
        }
        dex = decodedDex ?? []
        // Files from before items existed have neither key: start at the current segment so nothing is granted
        // retroactively. Decided here, so reading the same file again gives the same result. Exactly one of the two
        // keys, or a null value, is a damaged save (decoding throws and the file is kept).
        let decodedItems: [ItemGrant]
        let rolled: Int
        if c.contains(.items) || c.contains(.itemSegmentsRolled) {
            decodedItems = try c.decode([ItemGrant].self, forKey: .items)
            rolled = try c.decode(Int.self, forKey: .itemSegmentsRolled)
            // The checkpoint always equals the current partner's segment count (settle rolls right after steps change).
            guard rolled == ItemDrop.segment(forSteps: monster.totalCreditedSteps) else {
                throw DecodingError.dataCorruptedError(forKey: .itemSegmentsRolled, in: c,
                    debugDescription: "itemSegmentsRolled \(rolled) does not match \(monster.totalCreditedSteps) credited steps")
            }
        } else {
            decodedItems = []
            rolled = ItemDrop.segment(forSteps: monster.totalCreditedSteps)
        }
        var seenGrants = Set<String>()
        let validItems = rolled >= 0 && decodedItems.allSatisfy { grant in
            grant.segment >= 1 && !grant.itemId.isEmpty
                && (grant.monsterId != monster.id || grant.segment <= rolled)
                && seenGrants.insert("\(grant.monsterId.uuidString)#\(grant.segment)").inserted
        }
        guard validItems else {
            throw DecodingError.dataCorruptedError(forKey: .items, in: c,
                debugDescription: "items have a duplicate or out-of-range segment, or an empty id")
        }
        items = decodedItems
        itemSegmentsRolled = rolled
    }

    /// What the iPhone gets: one entry per item id (first grant order), not the whole ledger, so the snapshot
    /// stays small however many items were found.
    public var itemSummaries: [ItemSummary] {
        var order: [String] = []
        var found: [String: ItemSummary] = [:]
        for grant in items {
            let current = grant.monsterId == monster.id ? 1 : 0
            if let known = found[grant.itemId] {
                found[grant.itemId] = ItemSummary(itemId: grant.itemId, count: known.count + 1,
                                                  firstGrantedAt: min(known.firstGrantedAt, grant.grantedAt),
                                                  currentPartnerCount: known.currentPartnerCount + current)
            } else {
                order.append(grant.itemId)
                found[grant.itemId] = ItemSummary(itemId: grant.itemId, count: 1, firstGrantedAt: grant.grantedAt,
                                                  currentPartnerCount: current)
            }
        }
        return order.compactMap { found[$0] }
    }

    public func count(of itemId: String) -> Int { items.lazy.filter { $0.itemId == itemId }.count }
    public func owns(_ itemId: String) -> Bool { items.contains { $0.itemId == itemId } }

    public var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    public mutating func enroll(at date: Date) {
        if enrolledAt == nil { enrolledAt = date }
    }

    public mutating func settle(day: Date, steps: Int?, distance: Double?) {
        var generator = SystemRandomNumberGenerator()
        settle(day: day, steps: steps, distance: distance, at: nil, using: &generator)
    }

    /// `at` is the settlement time recorded in the dex (defaults to `day`).
    public mutating func settle(day: Date, steps: Int?, distance: Double?, at: Date? = nil,
                                using generator: inout some RandomNumberGenerator) {
        settle(day: day, steps: steps, distance: distance, at: at, committedCardId: monster.cardId, using: &generator)
    }

    /// `committedCardId` is the partner's card in the state a whole reconcile started from (nil: none yet). Only that
    /// card narrows the item draw, so a card drawn later in the same batch never changes the drops, and neither does
    /// the wall clock.
    public mutating func settle(day: Date, steps: Int?, distance: Double?, at: Date? = nil,
                                committedCardId: String?, using generator: inout some RandomNumberGenerator) {
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
            rollItems(at: at ?? day, committedCardId: committedCardId)
            advanceIfReady(at: at ?? day, using: &generator)
            revision += 1
        }
    }

    // Upgrade the original built-in starter in place so phone caches keep the same partner ID.
    public mutating func migrateLegacyStarter(at date: Date = .now) {
        var generator = SystemRandomNumberGenerator()
        migrateLegacyStarter(at: date, using: &generator)
    }

    public mutating func migrateLegacyStarter(at date: Date, using generator: inout some RandomNumberGenerator) {
        guard monster.speciesId == "starter_acorn", monster.name == "도토롱" else { return }
        monster.speciesId = Monster.eggSpeciesId
        monster.name = Monster.eggName
        recordDex(speciesId: Monster.eggSpeciesId, steps: 0, at: createdAt, cardId: nil)
        advanceIfReady(at: date, using: &generator)
        revision += 1
    }

    /// Brings a state saved before evolution cards existed (no `cardId`, no `dex`) onto the card catalog.
    /// Idempotent: bumps `revision` only when something changed.
    public mutating func migrateToEvolutionCatalog(at date: Date = .now) {
        var generator = SystemRandomNumberGenerator()
        migrateToEvolutionCatalog(at: date, using: &generator)
    }

    public mutating func migrateToEvolutionCatalog(at date: Date, using generator: inout some RandomNumberGenerator) {
        let before = (monster, dex)
        if monster.isEgg {
            recordDex(speciesId: Monster.eggSpeciesId, steps: 0, at: createdAt, cardId: nil)
        } else if monster.cardId == nil {
            migrateUncardedMonster(at: date, using: &generator)
        } else {
            if SpeciesCatalog.info(id: monster.speciesId) != nil, !dex.contains(where: { $0.speciesId == Monster.eggSpeciesId }) {
                dex.insert(DexEntry(speciesId: Monster.eggSpeciesId, firstMetAt: createdAt, firstMetSteps: 0, cardId: nil), at: 0)
            }
            recordDex(speciesId: monster.speciesId, steps: stageThreshold(monster.stage),
                      at: date, cardId: monster.cardId)
        }
        advanceIfReady(at: date, using: &generator)
        if (monster, dex) != before { revision += 1 }
    }

    private mutating func migrateUncardedMonster(at date: Date, using generator: inout some RandomNumberGenerator) {
        let speciesId = monster.speciesId
        if SpeciesCatalog.info(id: speciesId) != nil {
            recordDex(speciesId: Monster.eggSpeciesId, steps: 0, at: createdAt, cardId: nil)
        }
        if speciesId == SpeciesCatalog.legacyPoyomonId {
            // Poyomon belongs to no card: keep it in the dex and reassign the partner to a random card.
            recordDex(speciesId: speciesId, steps: Monster.stepsToHatch, at: date, cardId: nil)
            hatch(at: date, using: &generator)
        } else if let card = SpeciesCatalog.cards.first(where: { $0.stage(of: speciesId) == 0 }) {
            monster.cardId = card.id
            recordDex(speciesId: speciesId, steps: Monster.stepsToHatch, at: date, cardId: card.id)
        } else {
            // Unknown species: leave it alone, only record it.
            recordDex(speciesId: speciesId, steps: monster.totalCreditedSteps, at: date, cardId: nil)
            #if DEBUG
            print("DigiWalkerCore: unknown speciesId \(speciesId); evolution skipped")
            #endif
        }
    }

    /// Rolls every 5,000-step segment not rolled yet, one at a time. Runs before evolution so an item found in
    /// this settlement can unlock that evolution. Uses `ItemDrop`, never the evolution generator.
    private mutating func rollItems(at date: Date, committedCardId: String?) {
        let reached = ItemDrop.segment(forSteps: monster.totalCreditedSteps)
        while itemSegmentsRolled < reached {
            let segment = itemSegmentsRolled + 1
            itemSegmentsRolled = segment
            // A grant for this segment already on file (never expected) is kept; no second one is added.
            guard !items.contains(where: { $0.monsterId == monster.id && $0.segment == segment }),
                  let itemId = ItemDrop.roll(monsterId: monster.id, segment: segment, preferred: preferredItemIds(committedCardId: committedCardId))
            else { continue }
            items.append(ItemGrant(itemId: itemId, monsterId: monster.id, segment: segment, grantedAt: date))
        }
    }

    /// Items still missing that would unlock a species on the current card. Only a card that was already fixed when
    /// the reconcile started counts: a card drawn during this very reconcile differs between retries after a failed
    /// save, so those segments roll over the whole catalog instead. No wall clock is involved.
    private func preferredItemIds(committedCardId: String?) -> [String] {
        guard let card = monster.card, card.id == committedCardId else { return [] }
        return card.requiredItemIds.filter { !owns($0) }
    }

    private func stageThreshold(_ stage: Int?) -> Int {
        stage.map(EvolutionCard.requiredSteps(stage:)) ?? monster.totalCreditedSteps
    }

    private mutating func recordDex(speciesId: String, steps: Int, at date: Date, cardId: String?) {
        guard !speciesId.isEmpty, !dex.contains(where: { $0.speciesId == speciesId }) else { return }
        dex.append(DexEntry(speciesId: speciesId, firstMetAt: date, firstMetSteps: steps, cardId: cardId))
    }

    /// Uniform pick that always consumes exactly one generator value, so draws are predictable in tests.
    private static func pick<T>(_ items: [T], using generator: inout some RandomNumberGenerator) -> T? {
        guard !items.isEmpty else { return nil }
        let draw = generator.next()
        let index = draw.multipliedFullWidth(by: UInt64(items.count)).high
        return items[Int(index)]
    }

    private mutating func setSpecies(_ slot: CardSlot, card: EvolutionCard, at date: Date) {
        monster.speciesId = slot.speciesId
        monster.name = SpeciesCatalog.info(id: slot.speciesId)?.name ?? slot.speciesId
        monster.cardId = card.id
        recordDex(speciesId: slot.speciesId, steps: stageThreshold(card.stage(of: slot.speciesId)),
                  at: date, cardId: card.id)
    }

    /// Picks a random card and one of its stage 0 species.
    private mutating func hatch(at date: Date, using generator: inout some RandomNumberGenerator) {
        guard let card = Self.pick(SpeciesCatalog.cards, using: &generator),
              let slot = Self.pick(card.eligible(stage: 0), using: &generator) else { return }
        setSpecies(slot, card: card, at: date)
    }

    /// Hatches an egg at 500 steps, then evolves at the cumulative thresholds of `EvolutionCard.requiredSteps`, drawing separately each time.
    private mutating func advanceIfReady(at date: Date, using generator: inout some RandomNumberGenerator) {
        if monster.isEgg, monster.totalCreditedSteps >= Monster.stepsToHatch {
            hatch(at: date, using: &generator)
        }
        while let card = monster.card, let stage = card.stage(of: monster.speciesId),
              stage + 1 < EvolutionCard.stageCount,
              monster.totalCreditedSteps >= EvolutionCard.requiredSteps(stage: stage + 1),
              let slot = Self.pick(card.eligible(stage: stage + 1, owning: Set(items.map(\.itemId))), using: &generator) {
            setSpecies(slot, card: card, at: date)
        }
    }

    public mutating func recordObservation(steps: Int?, at date: Date) {
        if steps != todaySteps || observedAt.map({ !calendar.isDate($0, inSameDayAs: date) }) != false {
            todaySteps = steps
            observedAt = date
            revision += 1
        }
    }

    public var snapshot: MonsterSnapshot {
        MonsterSnapshot(schemaVersion: MonsterSnapshot.currentSchemaVersion, revision: revision, createdAt: createdAt,
                        monster: monster, todaySteps: todaySteps, observedAt: observedAt, timeZone: timeZone,
                        dex: dex, items: itemSummaries)
    }
}

public struct MonsterSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 3
    public static let supportedSchemaVersions: Set<Int> = [1, 2, 3]

    public let schemaVersion: Int
    public let revision: Int
    public let createdAt: Date
    public let monster: Monster
    public let todaySteps: Int?
    public let observedAt: Date?
    public let timeZone: TimeZone?
    /// Nil for v1 snapshots (the watch had no dex yet).
    public let dex: [DexEntry]?
    /// Nil before v3 (the watch had no items yet). v3 always carries the summary, possibly empty. The full ledger
    /// (ids, times) stays in the watch's state file.
    public let items: [ItemSummary]?

    public init(schemaVersion: Int, revision: Int, createdAt: Date, monster: Monster, todaySteps: Int?,
                observedAt: Date?, timeZone: TimeZone?, dex: [DexEntry]? = nil, items: [ItemSummary]? = nil) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.createdAt = createdAt
        self.monster = monster
        self.todaySteps = todaySteps
        self.observedAt = observedAt
        self.timeZone = timeZone
        self.dex = dex
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, revision, createdAt, monster, todaySteps, observedAt, timeZone, dex, items
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        revision = try c.decode(Int.self, forKey: .revision)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        monster = try c.decode(Monster.self, forKey: .monster)
        todaySteps = try c.decodeIfPresent(Int.self, forKey: .todaySteps)
        observedAt = try c.decodeIfPresent(Date.self, forKey: .observedAt)
        timeZone = try c.decodeIfPresent(TimeZone.self, forKey: .timeZone)
        dex = try c.decodeIfPresent([DexEntry].self, forKey: .dex)
        items = try c.decodeIfPresent([ItemSummary].self, forKey: .items)
    }

    private var hasValidDex: Bool {
        // v1 predates the dex; a v1 snapshot carrying one would skip the v2 checks, so reject it.
        guard schemaVersion >= 2 else { return dex == nil }
        guard let dex, !dex.isEmpty else { return false }
        var seen = Set<String>()
        return dex.allSatisfy { !$0.speciesId.isEmpty && $0.firstMetSteps >= 0 && seen.insert($0.speciesId).inserted }
            && seen.contains(monster.speciesId)
    }

    private var hasValidItems: Bool {
        // Like the dex: older versions must not carry items, so they cannot skip the v3 checks.
        guard schemaVersion >= 3 else { return items == nil }
        guard let items else { return false }
        var seen = Set<String>()
        // The current partner cannot have found more items than it has 5,000-step segments.
        let limit = ItemDrop.segment(forSteps: monster.totalCreditedSteps)
        var fromCurrent = 0
        for item in items {
            guard !item.itemId.isEmpty, item.count >= 1, (0...item.count).contains(item.currentPartnerCount),
                  seen.insert(item.itemId).inserted else { return false }
            // Compare before adding so a crafted huge count cannot overflow.
            guard item.currentPartnerCount <= limit - fromCurrent else { return false }
            fromCurrent += item.currentPartnerCount
        }
        return true
    }

    public func supersedes(_ cached: Self?) -> Bool {
        guard Self.supportedSchemaVersions.contains(schemaVersion), revision >= 0, monster.experience >= 0,
              monster.totalCreditedSteps >= 0, monster.distanceMeters >= 0,
              (todaySteps ?? 0) >= 0, !monster.name.isEmpty, !monster.speciesId.isEmpty,
              hasValidDex, hasValidItems else { return false }
        guard let cached else { return true }
        // Same partner and revision: only a higher schema replaces it (a watch update republishes v2 as v3).
        if monster.id == cached.monster.id {
            return revision > cached.revision || (revision == cached.revision && schemaVersion > cached.schemaVersion)
        }
        return createdAt > cached.createdAt
    }
}
