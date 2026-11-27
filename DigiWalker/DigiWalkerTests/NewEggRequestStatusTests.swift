import DigiWalkerCore
import Foundation
import Testing
@testable import DigiWalker

@MainActor
struct NewEggRequestStatusTests {
    private static let partner = "7770E692-324B-4A27-90EA-437743B4195A"
    private static let otherPartner = "1C2D3E4F-0000-4A27-90EA-437743B4195A"

    /// A snapshot built from JSON (like ItemModelTests). `experience` stays in the monster to prove old keys are ignored.
    private func snapshot(version: Int = 4, steps: Int = 85_000, species: String = "wargreymon",
                          id: String = partner, generation: Int = 0, revision: Int = 5,
                          items: String = #"[{"itemId":"digicore","count":2,"firstGrantedAt":821692800,"currentPartnerCount":2}]"#) throws -> MonsterSnapshot {
        let cardPart = species == "digitama" ? "" : #","cardId":"agu_ex""#
        let genPart = version >= 4 ? #","generation":\#(generation)"# : ""
        let itemPart = version >= 3 ? #","items":\#(items)"# : ""
        let json = #"{"schemaVersion":\#(version),"revision":\#(revision),"createdAt":821692800,"monster":{"id":"\#(id)","speciesId":"\#(species)","name":"워그레이몬","experience":9,"totalCreditedSteps":\#(steps),"distanceMeters":0\#(cardPart)},"timeZone":{"identifier":"GMT"},"dex":[{"speciesId":"\#(species)","firstMetAt":821692800,"firstMetSteps":0}]\#(itemPart)\#(genPart)}"#
        return try JSONDecoder().decode(MonsterSnapshot.self, from: Data(json.utf8))
    }

    private func pending(_ phase: PendingNewEgg.Phase, target: String = partner) -> PendingNewEgg {
        PendingNewEgg(request: NewEggRequest(targetMonsterId: UUID(uuidString: target)!, requestedAt: Date(timeIntervalSince1970: 0)),
                      phase: phase)
    }

    @Test func buttonOnlyForAFinishedPartnerOnV4() throws {
        #expect(NewEggRequestStatus.evaluate(snapshot: nil, pending: nil) == .hidden)
        #expect(NewEggRequestStatus.evaluate(snapshot: try snapshot(), pending: nil) == .available)
        #expect(NewEggRequestStatus.evaluate(snapshot: try snapshot(steps: 84_999), pending: nil) == .hidden)
        #expect(NewEggRequestStatus.evaluate(snapshot: try snapshot(steps: 90_000, species: "greymon"), pending: nil) == .hidden)
    }

    @Test func oldWatchCacheAsksForAnUpdateInsteadOfOfferingTheButton() throws {
        let v3 = try snapshot(version: 3)
        #expect(v3.supersedes(nil))
        #expect(NewEggRequestStatus.evaluate(snapshot: v3, pending: nil) == .needsWatchUpdate)
        #expect(NewEggRequestStatus.evaluate(snapshot: try snapshot(version: 3, steps: 80_000), pending: nil) == .hidden)
    }

    @Test func pendingPhasesShowWaitingAndBlockASecondRequest() throws {
        let shot = try snapshot()
        #expect(NewEggRequestStatus.evaluate(snapshot: shot, pending: pending(.queued)) == .queued)
        #expect(NewEggRequestStatus.evaluate(snapshot: shot, pending: pending(.delivered)) == .delivered)
        #expect(NewEggRequestStatus.evaluate(snapshot: shot, pending: pending(.failed)) == .failed)
        #expect(NewEggControls.message(for: .queued) == "워치에 연결되면 시작됩니다")
    }

    @Test func notLinkedWatchShowsConnectionNoteInsteadOfTheButton() throws {
        let shot = try snapshot()
        #expect(NewEggRequestStatus.evaluate(snapshot: shot, pending: nil, watchLinked: false) == .notConnected)
        #expect(NewEggControls.message(for: .notConnected) == "워치와 연결을 확인해 주세요")
        #expect(NewEggRequestStatus.evaluate(snapshot: shot, pending: pending(.queued), watchLinked: false) == .queued)
        #expect(NewEggRequestStatus.evaluate(snapshot: try snapshot(version: 3), pending: nil, watchLinked: false) == .needsWatchUpdate)
        #expect(NewEggRequestStatus.evaluate(snapshot: try snapshot(steps: 100), pending: nil, watchLinked: false) == .hidden)
    }

    @Test func onlyQueuedRequestsAreCalledCancellable() {
        #expect(NewEggControls.cancelTitle(for: .queued) == "요청 취소")
        #expect(NewEggControls.cancelTitle(for: .delivered) == "대기 표시 지우기")
        #expect(NewEggControls.cancelTitle(for: .failed) == "대기 표시 지우기")
        #expect(NewEggControls.message(for: .delivered).contains("새 알이 시작될 수 있어요"))
    }

    @Test func transferResultsMoveThePhaseForward() {
        var queued = pending(.queued)
        #expect(queued.applyTransferResult(failed: false) && queued.phase == .delivered)
        #expect(queued.applyTransferResult(failed: true) && queued.phase == .failed) // late error for the same request
        #expect(!queued.applyTransferResult(failed: false) && queued.phase == .failed)
        var delivered = pending(.delivered)
        #expect(!delivered.applyTransferResult(failed: false) && delivered.phase == .delivered)
        var failedFirst = pending(.queued)
        #expect(failedFirst.applyTransferResult(failed: true) && failedFirst.phase == .failed)
    }

    @Test func discardRemovesTheFileAndTreatsMissingAsDone() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "pending-\(UUID().uuidString).json")
        try Data("{}".utf8).write(to: url)
        #expect(PhoneSyncService.discard(url))
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(PhoneSyncService.discard(url))
        // A blanked file never decodes as a request.
        try Data("null".utf8).write(to: url)
        #expect((try? StateFile<PendingNewEgg>(url: url).load()) == nil)
        try? FileManager.default.removeItem(at: url)
    }

    @Test func requestIsResolvedByAnotherPartnerNotByTheSameOne() throws {
        let sameAfterRefresh = try snapshot(revision: 6)
        #expect(!pending(.queued).isResolved(by: sameAfterRefresh))
        // The watch started a new egg: another id, higher generation.
        let newEgg = try snapshot(steps: 0, species: "digitama", id: Self.otherPartner, generation: 1, revision: 7, items: "[]")
        #expect(newEgg.supersedes(sameAfterRefresh))
        #expect(pending(.delivered).isResolved(by: newEgg))
        // A stale pending for an old partner never blocks the button of the current finished partner.
        let current = try snapshot(id: Self.otherPartner, generation: 1, revision: 9)
        #expect(NewEggRequestStatus.evaluate(snapshot: current, pending: pending(.queued)) == .available)
    }

    @Test func pendingStateRoundTripsThroughJSON() throws {
        let original = pending(.delivered)
        let decoded = try JSONDecoder().decode(PendingNewEgg.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test func legacyExperienceKeyIsIgnoredInV3AndV4() throws {
        #expect(try snapshot(version: 3).monster.totalCreditedSteps == 85_000)
        #expect(try snapshot().monster.canStartNewEgg)
    }

    @Test func itemRowsShowCurrentCountAndUsedUpItemsAsNotOwned() throws {
        let model = ItemModel(snapshot: try snapshot(items: #"[{"itemId":"digicore","count":1,"firstGrantedAt":821692800,"currentPartnerCount":1}]"#))
        let rows = model.sections.flatMap(\.rows)
        #expect(rows.first { $0.id == "digicore" }?.count == 1)
        #expect(rows.first { $0.id == "digicode" }?.owned == false)
        #expect(model.ownedKinds == 1)
    }

    @Test func cancelOnlyClearsWhenTheTransferWasReallyCancelled() {
        for phase in [PendingNewEgg.Phase.queued, .preparing] {
            var found = pending(phase)
            #expect(found.resolveCancel(transferCancelled: true) == .cleared)
            var missing = pending(phase)
            #expect(missing.resolveCancel(transferCancelled: false) == .keptAsDelivered)
            #expect(missing.phase == .delivered)
            #expect(NewEggRequestStatus.evaluate(snapshot: try? snapshot(), pending: missing) == .delivered)
        }
        for phase in [PendingNewEgg.Phase.delivered, .failed] {
            var later = pending(phase)
            #expect(later.resolveCancel(transferCancelled: false) == .cleared)
        }
    }

    @Test func preparingRequestIsResentUnlessItsTransferIsStillQueued() throws {
        #expect(pending(.preparing).reconciliation(stillQueued: false) == .resend)
        #expect(pending(.preparing).reconciliation(stillQueued: true) == .markQueued)
        #expect(pending(.queued).reconciliation(stillQueued: false) == .markDelivered)
        #expect(pending(.queued).reconciliation(stillQueued: true) == .none)
        #expect(pending(.delivered).reconciliation(stillQueued: false) == .none)
        #expect(pending(.failed).reconciliation(stillQueued: false) == .none)
        #expect(NewEggRequestStatus.evaluate(snapshot: try snapshot(), pending: pending(.preparing)) == .queued)
        var preparing = pending(.preparing)
        #expect(preparing.applyTransferResult(failed: false) && preparing.phase == .delivered)
        let decoded = try JSONDecoder().decode(PendingNewEgg.self, from: JSONEncoder().encode(pending(.preparing)))
        #expect(decoded.phase == .preparing)
    }

    @Test func dialogIsOnlyValidForThePartnerItWasOpenedFor() throws {
        let target = try #require(UUID(uuidString: Self.partner))
        let other = try #require(UUID(uuidString: Self.otherPartner))
        #expect(ContentView.dialogStillValid(target: target, cached: target))
        #expect(!ContentView.dialogStillValid(target: target, cached: other))
        #expect(!ContentView.dialogStillValid(target: target, cached: nil))
        #expect(!ContentView.dialogStillValid(target: nil, cached: target))
    }

    @Test func v3CacheShowsNeitherTheOfferNorTheCountdown() throws {
        #expect(ContentView.offersNewEgg(try snapshot()))
        let v3 = try snapshot(version: 3)
        #expect(!ContentView.offersNewEgg(v3))
        #expect(PartnerGrowthView.finalStageHint(monster: v3.monster, offersNewEgg: false) == "최종 단계")
        let below = try snapshot(version: 3, steps: 80_000)
        #expect(PartnerGrowthView.finalStageHint(monster: below.monster, offersNewEgg: false) == "최종 단계")
        #expect(PartnerGrowthView.finalStageHint(monster: below.monster, offersNewEgg: true) == nil)
        #expect(PartnerGrowthView.finalStageHint(monster: try snapshot().monster, offersNewEgg: true) == "새 알을 키울 수 있어요")
    }
}
