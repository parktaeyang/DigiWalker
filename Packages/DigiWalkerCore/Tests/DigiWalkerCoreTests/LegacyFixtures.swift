import Foundation
@testable import DigiWalkerCore

/// JSON produced by the code at commit 96819e2 (before cards and dex existed), via JSONEncoder with default strategies.
/// Botamon/poyomon step and XP values were scaled ×10 when the stage threshold moved from 500 to 5,000 steps.
/// Each state was enrolled at createdAt (1_800_000_000), settled on day 1 and day 2 (10 steps), and observed.
enum LegacyFixtures {
    static let createdAt = Date(timeIntervalSince1970: 1_800_000_000)

    static func gameState(_ json: String) throws -> GameState {
        try JSONDecoder().decode(GameState.self, from: Data(json.utf8))
    }

    /// Egg with 9 + 10 credited steps.
    static let egg = #"{"createdAt":821692800,"enrolledAt":821692800,"lastStepDay":821750400,"ledgers":[821750400,{"creditedDistanceMeters":0,"creditedSteps":10,"creditedXP":0},821664000,{"creditedDistanceMeters":1234.5,"creditedSteps":9,"creditedXP":0}],"monster":{"distanceMeters":1234.5,"experience":0,"id":"2540C279-A1C6-49E8-84FA-65F6F0500F83","name":"디지타마","speciesId":"digitama","totalCreditedSteps":19},"observedAt":821779200,"revision":3,"timeZone":{"identifier":"GMT"},"todaySteps":10}"#

    /// Botamon, 12000 + 10 steps.
    static let botamon = #"{"createdAt":821692800,"enrolledAt":821692800,"lastStepDay":821750400,"ledgers":[821664000,{"creditedDistanceMeters":1234.5,"creditedSteps":12000,"creditedXP":1200},821750400,{"creditedDistanceMeters":0,"creditedSteps":10,"creditedXP":0}],"monster":{"distanceMeters":1234.5,"experience":1200,"id":"DEAFE761-E7A5-4F75-9EEF-06FB3A131F6B","name":"깜몬","speciesId":"botamon","totalCreditedSteps":12010},"observedAt":821779200,"revision":3,"timeZone":{"identifier":"GMT"},"todaySteps":10}"#

    /// Punimon, 300 + 10 steps (below 5,000 only because the fixture was seeded directly).
    static let punimon = #"{"createdAt":821692800,"enrolledAt":821692800,"lastStepDay":821750400,"ledgers":[821750400,{"creditedDistanceMeters":0,"creditedSteps":10,"creditedXP":0},821664000,{"creditedDistanceMeters":1234.5,"creditedSteps":300,"creditedXP":30}],"monster":{"distanceMeters":1234.5,"experience":30,"id":"59BC3CE7-4075-4D46-85F1-1A8E82259DD4","name":"푸니몬","speciesId":"punimon","totalCreditedSteps":310},"observedAt":821779200,"revision":3,"timeZone":{"identifier":"GMT"},"todaySteps":10}"#

    /// Poyomon, 8000 + 10 steps.
    static let poyomon800 = #"{"createdAt":821692800,"enrolledAt":821692800,"lastStepDay":821750400,"ledgers":[821664000,{"creditedDistanceMeters":1234.5,"creditedSteps":8000,"creditedXP":800},821750400,{"creditedDistanceMeters":0,"creditedSteps":10,"creditedXP":0}],"monster":{"distanceMeters":1234.5,"experience":800,"id":"E1618DC6-0E62-4F3A-B0DB-E57C63D07A1F","name":"포요몬","speciesId":"poyomon","totalCreditedSteps":8010},"observedAt":821779200,"revision":3,"timeZone":{"identifier":"GMT"},"todaySteps":10}"#

    /// Poyomon, 16000 + 10 steps.
    static let poyomon1600 = #"{"createdAt":821692800,"enrolledAt":821692800,"lastStepDay":821750400,"ledgers":[821664000,{"creditedDistanceMeters":1234.5,"creditedSteps":16000,"creditedXP":1600},821750400,{"creditedDistanceMeters":0,"creditedSteps":10,"creditedXP":0}],"monster":{"distanceMeters":1234.5,"experience":1600,"id":"ABBAAD1B-D52A-4EE8-B334-17E35C88E781","name":"포요몬","speciesId":"poyomon","totalCreditedSteps":16010},"observedAt":821779200,"revision":3,"timeZone":{"identifier":"GMT"},"todaySteps":10}"#

    /// Unknown species id.
    static let unknown = #"{"createdAt":821692800,"enrolledAt":821692800,"lastStepDay":821750400,"ledgers":[821750400,{"creditedDistanceMeters":0,"creditedSteps":10,"creditedXP":0},821664000,{"creditedDistanceMeters":1234.5,"creditedSteps":700,"creditedXP":70}],"monster":{"distanceMeters":1234.5,"experience":70,"id":"AD744B38-2CCC-4341-8837-BD94D6D0C895","name":"???","speciesId":"mystery","totalCreditedSteps":710},"observedAt":821779200,"revision":3,"timeZone":{"identifier":"GMT"},"todaySteps":10}"#

    /// v1 snapshot of the botamon state.
    static let snapshotV1 = #"{"createdAt":821692800,"monster":{"distanceMeters":1234.5,"experience":120,"id":"7770E692-324B-4A27-90EA-437743B4195A","name":"깜몬","speciesId":"botamon","totalCreditedSteps":12010},"observedAt":821779200,"revision":3,"schemaVersion":1,"timeZone":{"identifier":"GMT"},"todaySteps":10}"#
}
