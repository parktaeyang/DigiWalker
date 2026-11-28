#if DEMO_DEX
import DigiWalkerCore
import Foundation

/// Test-only data for an iPhone without an Apple Watch (battle testing). Compiled only when the build passes
/// `SWIFT_ACTIVE_COMPILATION_CONDITIONS` containing `DEMO_DEX`; normal Debug/Release builds never include it.
/// The cache lives in memory only: nothing is written to disk, so a later real watch snapshot is unaffected.
enum DemoDex {
    /// Partner: Agumon (growth stage) with every card species in the dex.
    static func cache(now: Date = .now) -> PhoneCache? {
        let base = GameState(now: now).snapshot
        guard let data = try? JSONEncoder().encode(base),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var monster = root["monster"] as? [String: Any] else { return nil }

        monster["speciesId"] = "agumon"
        monster["name"] = SpeciesCatalog.info(id: "agumon")?.name ?? "아구몬"
        monster["cardId"] = "agu_ex"
        monster["totalCreditedSteps"] = 20_000
        root["monster"] = monster

        let metAt = now.timeIntervalSinceReferenceDate
        var seen = Set<String>()
        var dex: [[String: Any]] = []
        for card in SpeciesCatalog.cards {
            for slots in card.stages {
                for slot in slots where seen.insert(slot.speciesId).inserted {
                    dex.append(["speciesId": slot.speciesId, "firstMetAt": metAt, "firstMetSteps": 0, "cardId": card.id])
                }
            }
        }
        root["dex"] = dex

        guard let patched = try? JSONSerialization.data(withJSONObject: root),
              let snapshot = try? JSONDecoder().decode(MonsterSnapshot.self, from: patched),
              snapshot.supersedes(nil) else { return nil }
        return PhoneCache(snapshot: snapshot, receivedAt: now)
    }
}
#endif
