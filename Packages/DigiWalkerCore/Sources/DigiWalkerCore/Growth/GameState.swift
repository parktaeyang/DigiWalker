import Foundation

public struct Monster: Codable, Equatable, Sendable {
    public let id: UUID
    public static let eggSpeciesId = SpeciesCatalog.eggId
    fileprivate static let eggName = "디지타마"
    public static let stepsToHatch = EvolutionCard.requiredSteps(stage: 0)
    public var isEgg: Bool { speciesId == Self.eggSpeciesId }
    public fileprivate(set) var speciesId: String
    public fileprivate(set) var name: String
    public fileprivate(set) var totalCreditedSteps = 0
    public fileprivate(set) var distanceMeters = 0.0
    /// Evolution card fixed at hatching. Nil for eggs and for states saved before cards existed.
    public fileprivate(set) var cardId: String?
    /// Credited steps at which a finished (stage 5) partner may be replaced by a new egg: ultimate + 10,000.
    public static let stepsForNewEgg = EvolutionCard.requiredSteps(stage: EvolutionCard.stageCount - 1) + 10_000
    /// True for a final-stage partner of a known card with at least `stepsForNewEgg` credited steps.
    public var canStartNewEgg: Bool {
        !isEgg && stage == EvolutionCard.stageCount - 1 && totalCreditedSteps >= Self.stepsForNewEgg
    }
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
        case id, speciesId, name, totalCreditedSteps, distanceMeters, cardId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        speciesId = try c.decode(String.self, forKey: .speciesId)
        name = try c.decode(String.self, forKey: .name)
        // A legacy `experience` key is ignored: growth is driven by steps only.
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
    /// Latest end of a query range whose steps were settled. Never decreases, even if the clock is set back (unlike
    /// `observedAt`, which is for display). A new egg starts no earlier than this. Nil in files from before it existed.
    public private(set) var creditedThrough: Date?
    /// Species met by this partner generation, in the order they were met. Never contains duplicates.
    public private(set) var dex: [DexEntry] = []
    /// Items received so far, oldest first. Belongs to the whole game, so it stays for the next partner.
    /// Duplicates are allowed (a count), but `(monsterId, segment)` is unique. Append-only: use is recorded in `itemUses`.
    public private(set) var items: [ItemGrant] = []
    /// Items consumed by evolutions, oldest first, append-only. `(monsterId, stage)` is unique.
    /// Held count of an item = grants - uses.
    public private(set) var itemUses: [ItemUse] = []
    /// 0 for the first partner, +1 for every new egg.
    public private(set) var generation = 0
    /// Card of the previous partner; only the next hatch uses it (to avoid the same card), then it is cleared.
    public private(set) var previousCardId: String?
    /// Last 5,000-step segment of the current partner whose drop was already rolled (win or lose).
    public private(set) var itemSegmentsRolled = 0
    /// When the current partner began (the new egg's start), nil for the first partner (then `enrolledAt` counts).
    /// Present exactly when `generation >= 1`. Like `enrolledAt` it is a step cutoff: nothing before it is read or
    /// credited, so steps taken (or synced late) before a new egg started never reach it.
    public private(set) var partnerSince: Date?
    /// Ledgers of the previous partner(s) for the day a new egg started, which the new partner's own ledger replaces
    /// (its read begins at `partnerSince`, so the old high-water mark has another meaning). Keeps the daily maximum
    /// of that day. Sums if several partners started on one day. Empty unless `partnerSince` is set.
    public private(set) var priorPartnerLedgers: [Date: DailyActivityLedger] = [:]

    /// First moment steps count for the current partner.
    public var stepCutoff: Date? {
        guard let enrolledAt else { return nil }
        return max(enrolledAt, partnerSince ?? enrolledAt)
    }

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
        case monster, createdAt, timeZone, revision, enrolledAt, lastStepDay, ledgers, todaySteps, observedAt, dex, creditedThrough
        case items, itemSegmentsRolled, itemUses, generation, previousCardId, partnerSince, priorPartnerLedgers
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
        creditedThrough = try c.decodeIfPresent(Date.self, forKey: .creditedThrough)
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
            // A save that has generation or itemUses is modern and always writes both item keys; losing them
            // would silently empty the inventory, so it is damage, not a legacy file.
            guard !c.contains(.generation), !c.contains(.itemUses) else {
                throw DecodingError.dataCorruptedError(forKey: .items, in: c,
                    debugDescription: "generation/itemUses present but items and itemSegmentsRolled are missing")
            }
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
        // Files from before item use have no `itemUses`: nothing is consumed retroactively. A null value is damage.
        // `generation` and `itemUses` arrive together: both missing is a legacy file, only one is damage.
        guard c.contains(.itemUses) == c.contains(.generation) else {
            throw DecodingError.dataCorruptedError(forKey: .itemUses, in: c,
                debugDescription: "itemUses and generation must both be present or both absent")
        }
        let decodedUses = c.contains(.itemUses) ? try c.decode([ItemUse].self, forKey: .itemUses) : []
        var usesByItem: [String: Int] = [:]
        var seenUses = Set<String>()
        let currentStage = monster.stage
        let validUses = decodedUses.allSatisfy { use in
            guard !use.itemId.isEmpty, !use.speciesId.isEmpty, use.stage >= 1,
                  seenUses.insert("\(use.monsterId.uuidString)#\(use.stage)").inserted else { return false }
            usesByItem[use.itemId, default: 0] += 1
            guard use.stage < EvolutionCard.stageCount else { return false }
            guard use.monsterId == monster.id else { return true }
            return currentStage.map { use.stage <= $0 } ?? false
        }
        var grantedByItem: [String: Int] = [:]
        for grant in decodedItems { grantedByItem[grant.itemId, default: 0] += 1 }
        guard validUses, usesByItem.allSatisfy({ $0.value <= grantedByItem[$0.key, default: 0] }) else {
            throw DecodingError.dataCorruptedError(forKey: .itemUses, in: c,
                debugDescription: "itemUses have a duplicate, an empty id, an out-of-range stage, or exceed the grants")
        }
        itemUses = decodedUses
        let decodedGeneration = c.contains(.generation) ? try c.decode(Int.self, forKey: .generation) : 0
        guard decodedGeneration >= 0 else {
            throw DecodingError.dataCorruptedError(forKey: .generation, in: c, debugDescription: "negative generation")
        }
        generation = decodedGeneration
        previousCardId = try c.decodeIfPresent(String.self, forKey: .previousCardId)
        // A partner after the first always has a dex (the egg is recorded at rebirth); a hatched-not-yet egg
        // also remembers the card it replaced. Losing either is damage, and must be caught before any migration
        // could fill the gap and hide it.
        if decodedGeneration >= 1 {
            guard !(decodedDex?.isEmpty ?? true) else {
                throw DecodingError.dataCorruptedError(forKey: .dex, in: c,
                    debugDescription: "dex is missing or empty at generation >= 1")
            }
            guard !monster.isEgg || previousCardId != nil else {
                throw DecodingError.dataCorruptedError(forKey: .previousCardId, in: c,
                    debugDescription: "previousCardId is missing for an unhatched egg at generation >= 1")
            }
        }
        partnerSince = try c.decodeIfPresent(Date.self, forKey: .partnerSince)
        // A partner after the first always has the key (possibly empty); only a legacy file (generation 0) may lack it.
        // A missing or null key at generation >= 1 means the file lost data.
        if decodedGeneration >= 1 {
            guard c.contains(.priorPartnerLedgers), !(try c.decodeNil(forKey: .priorPartnerLedgers)) else {
                throw DecodingError.dataCorruptedError(forKey: .priorPartnerLedgers, in: c,
                    debugDescription: "priorPartnerLedgers is missing or null at generation >= 1")
            }
        }
        priorPartnerLedgers = try c.decodeIfPresent([Date: DailyActivityLedger].self, forKey: .priorPartnerLedgers) ?? [:]
        // The start time exists exactly for partners after the first; prior ledgers need one.
        guard (partnerSince != nil) == (generation >= 1), partnerSince != nil || priorPartnerLedgers.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .partnerSince, in: c,
                debugDescription: "partnerSince must be present exactly when generation >= 1")
        }
    }

    /// What the iPhone gets: one entry per item id still held (first grant order), not the whole ledger, so the
    /// snapshot stays small however many items were found. `count` is grants minus uses; used-up items are left out.
    public var itemSummaries: [ItemSummary] {
        var order: [String] = []
        var granted: [String: Int] = [:]
        var first: [String: Date] = [:]
        var currentFound: [String: Int] = [:]
        for grant in items {
            if let known = first[grant.itemId] {
                first[grant.itemId] = min(known, grant.grantedAt)
            } else {
                order.append(grant.itemId)
                first[grant.itemId] = grant.grantedAt
            }
            granted[grant.itemId, default: 0] += 1
            if grant.monsterId == monster.id { currentFound[grant.itemId, default: 0] += 1 }
        }
        var used: [String: Int] = [:]
        for use in itemUses { used[use.itemId, default: 0] += 1 }
        return order.compactMap { id in
            let count = granted[id, default: 0] - used[id, default: 0]
            guard count >= 1, let firstGrantedAt = first[id] else { return nil }
            return ItemSummary(itemId: id, count: count, firstGrantedAt: firstGrantedAt,
                               currentPartnerCount: min(currentFound[id, default: 0], count))
        }
    }

    /// Items currently held: grants minus uses.
    public func count(of itemId: String) -> Int { heldCounts[itemId, default: 0] }
    public func owns(_ itemId: String) -> Bool { count(of: itemId) > 0 }
    private var ownedItemIds: Set<String> { Set(heldCounts.filter { $0.value > 0 }.keys) }

    /// Grants minus uses per item id in one pass over each list.
    private var heldCounts: [String: Int] { Self.heldCounts(grants: items, uses: itemUses[...]) }
    private static func heldCounts(grants: [ItemGrant], uses: ArraySlice<ItemUse>) -> [String: Int] {
        var held: [String: Int] = [:]
        for grant in grants { held[grant.itemId, default: 0] += 1 }
        for use in uses { held[use.itemId, default: 0] -= 1 }
        return held
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
        var generator = SystemRandomNumberGenerator()
        settle(day: day, steps: steps, distance: distance, at: nil, using: &generator)
    }

    /// `at` is the settlement time recorded in the dex (defaults to `day`).
    public mutating func settle(day: Date, steps: Int?, distance: Double?, at: Date? = nil,
                                using generator: inout some RandomNumberGenerator) {
        settle(day: day, steps: steps, distance: distance, at: at, committedCardId: monster.cardId,
               committedUseCount: itemUses.count, using: &generator)
    }

    /// `committedCardId` is the partner's card in the state a whole reconcile started from (nil: none yet), and
    /// `committedUseCount` is how many `itemUses` that state held (uses are append-only, so they are a prefix). Only
    /// that card and those uses narrow the item draw, so a card drawn or an item used later in the same batch never
    /// changes the drops, and neither does the wall clock.
    /// `steps` and `distance` must be measured from `max(start of day, stepCutoff)`: for the day containing the
    /// cutoff (enrollment or a new egg's start) that means from the cutoff on, never the whole day. `GrowthService`
    /// does this; a caller that passes a whole-day total for that day would credit steps from before the cutoff.
    public mutating func settle(day: Date, steps: Int?, distance: Double?, at: Date? = nil,
                                committedCardId: String?, committedUseCount: Int, using generator: inout some RandomNumberGenerator) {
        guard let cutoff = stepCutoff, day >= calendar.startOfDay(for: cutoff) else { return }
        if let at, steps != nil || distance != nil, at > (creditedThrough ?? .distantPast) { creditedThrough = at }
        let key = calendar.startOfDay(for: day)
        var ledger = ledgers[key] ?? DailyActivityLedger()
        if let steps {
            let high = max(ledger.creditedSteps, steps)
            monster.totalCreditedSteps += high - ledger.creditedSteps
            ledger.creditedSteps = high
            lastStepDay = max(key, lastStepDay ?? key)
        }
        if let distance, distance.isFinite, distance > ledger.creditedDistanceMeters {
            monster.distanceMeters += distance - ledger.creditedDistanceMeters
            ledger.creditedDistanceMeters = distance
        }
        if ledger != (ledgers[key] ?? DailyActivityLedger()) {
            ledgers[key] = ledger
            rollItems(at: at ?? day, committedCardId: committedCardId, committedUseCount: committedUseCount)
            advanceIfReady(at: at ?? day, using: &generator)
            revision += 1
        }
    }

    /// Replaces a finished partner with a new egg. Does nothing and returns false unless `target` is the current
    /// partner and `canStartNewEgg`; once applied the partner id changes, so repeating the same target is ignored.
    /// Ledgers, dex, items, uses, enrollment and revision continue; only the partner starts over at 0 steps.
    @discardableResult
    public mutating func startNewEgg(target: UUID, at date: Date, newMonsterId: UUID = UUID()) -> Bool {
        guard monster.id == target, monster.canStartNewEgg, newMonsterId != monster.id,
              !items.contains(where: { $0.monsterId == newMonsterId }),
              !itemUses.contains(where: { $0.monsterId == newMonsterId }) else { return false }
        previousCardId = monster.cardId
        monster = Monster(id: newMonsterId, speciesId: Monster.eggSpeciesId, name: Monster.eggName)
        itemSegmentsRolled = 0
        generation += 1
        // New step cutoff: the new partner only gets steps from `start` on. The clock never runs backwards: a start
        // before an already observed or earlier cutoff moment is moved up to it, so nothing already read is read again.
        // `creditedThrough` is the monotonic bound; `observedAt` stays as the fallback for files that lack it.
        let start = max(date, creditedThrough ?? date, observedAt ?? date, partnerSince ?? date, enrolledAt ?? date)
        // The ledger of the cutoff's day was measured from an earlier start, so it moves to `priorPartnerLedgers`
        // and the new partner starts that day at 0. The day comes from the final cutoff, not from `date`.
        let day = calendar.startOfDay(for: start)
        if let old = ledgers.removeValue(forKey: day) {
            var merged = priorPartnerLedgers[day] ?? DailyActivityLedger()
            merged.creditedSteps += old.creditedSteps
            merged.creditedDistanceMeters += old.creditedDistanceMeters
            priorPartnerLedgers[day] = merged
        }
        partnerSince = start
        recordDex(speciesId: Monster.eggSpeciesId, steps: 0, at: start, cardId: nil)
        revision += 1
        return true
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
    private mutating func rollItems(at date: Date, committedCardId: String?, committedUseCount: Int) {
        let reached = ItemDrop.segment(forSteps: monster.totalCreditedSteps)
        while itemSegmentsRolled < reached {
            let segment = itemSegmentsRolled + 1
            itemSegmentsRolled = segment
            // A grant for this segment already on file (never expected) is kept; no second one is added.
            guard !items.contains(where: { $0.monsterId == monster.id && $0.segment == segment }),
                  let itemId = ItemDrop.roll(monsterId: monster.id, segment: segment, preferred: preferredItemIds(committedCardId: committedCardId, committedUseCount: committedUseCount))
            else { continue }
            items.append(ItemGrant(itemId: itemId, monsterId: monster.id, segment: segment, grantedAt: date))
        }
    }

    /// Items still missing that would unlock a species on the current card. Only a card that was already fixed when
    /// the reconcile started counts: a card drawn during this very reconcile differs between retries after a failed
    /// save, so those segments roll over the whole catalog instead. No wall clock is involved.
    private func preferredItemIds(committedCardId: String?, committedUseCount: Int) -> [String] {
        guard let card = monster.card, card.id == committedCardId else { return [] }
        // Held count as of the start of the batch: every grant so far (grants only come from this deterministic
        // roll) minus only the uses that were already committed. Uses made during this batch come from the
        // evolution generator and differ between retries, so they must not steer the draw. An item a partner
        // used up in an earlier saved batch counts as missing again.
        let held = Self.heldCounts(grants: items, uses: itemUses.prefix(max(0, committedUseCount)))
        return card.requiredItemIds.filter { held[$0, default: 0] == 0 }
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
        // A new egg (generation >= 1) hatches from its own id, without the previous card, never from the generator.
        if generation >= 1 {
            guard let (card, slot) = HatchDraw.pick(monsterId: monster.id, excluding: previousCardId) else { return }
            setSpecies(slot, card: card, at: date)
            previousCardId = nil
            return
        }
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
              let slot = Self.pick(card.eligible(stage: stage + 1, owning: ownedItemIds), using: &generator) {
            setSpecies(slot, card: card, at: date)
            // A locked species that was really picked uses up one of its item.
            if let itemId = slot.requiredItemId {
                itemUses.append(ItemUse(itemId: itemId, monsterId: monster.id, speciesId: slot.speciesId,
                                        stage: stage + 1, usedAt: date))
            }
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
                        dex: dex, items: itemSummaries, generation: generation)
    }
}

public struct MonsterSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 4
    public static let supportedSchemaVersions: Set<Int> = [1, 2, 3, 4]

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
    /// Partner generation (0 for the first partner, +1 per new egg). Nil before v4; v4 always carries it. A new egg
    /// keeps `createdAt` but raises this, so `supersedes` can tell it from a stale snapshot of the old partner.
    public let generation: Int?

    public init(schemaVersion: Int, revision: Int, createdAt: Date, monster: Monster, todaySteps: Int?,
                observedAt: Date?, timeZone: TimeZone?, dex: [DexEntry]? = nil, items: [ItemSummary]? = nil,
                generation: Int? = nil) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.createdAt = createdAt
        self.monster = monster
        self.todaySteps = todaySteps
        self.observedAt = observedAt
        self.timeZone = timeZone
        self.dex = dex
        self.items = items
        self.generation = generation
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, revision, createdAt, monster, todaySteps, observedAt, timeZone, dex, items, generation
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
        generation = try c.decodeIfPresent(Int.self, forKey: .generation)
    }

    private var hasValidGeneration: Bool {
        // Like the dex and items: older versions must not carry it, v4 must.
        guard schemaVersion >= 4 else { return generation == nil }
        // Every new egg raises the revision, so a partner's generation can never exceed its revision.
        guard let generation else { return false }
        return generation >= 0 && generation <= revision
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
        guard Self.supportedSchemaVersions.contains(schemaVersion), revision >= 0,
              monster.totalCreditedSteps >= 0, monster.distanceMeters >= 0,
              (todaySteps ?? 0) >= 0, !monster.name.isEmpty, !monster.speciesId.isEmpty,
              hasValidDex, hasValidItems, hasValidGeneration else { return false }
        guard let cached else { return true }
        // Same partner and revision: only a higher schema replaces it (a watch update republishes v2 as v3).
        if monster.id == cached.monster.id {
            // A partner id never changes generation: that would be a forged or corrupted snapshot.
            guard (generation ?? 0) == (cached.generation ?? 0) else { return false }
            return revision > cached.revision || (revision == cached.revision && schemaVersion > cached.schemaVersion)
        }
        // Another partner: a reinstall (later createdAt, generation 0) or a new egg (same createdAt, higher
        // generation) wins; a late snapshot of an older partner (lower generation) loses.
        if createdAt != cached.createdAt { return createdAt > cached.createdAt }
        // Every new egg raises the revision too, so a higher generation with a lower or equal revision is not newer
        // (and an id change without a generation change is not a new egg at all).
        let (mine, theirs) = (generation ?? 0, cached.generation ?? 0)
        return mine > theirs && revision > cached.revision
    }
}
