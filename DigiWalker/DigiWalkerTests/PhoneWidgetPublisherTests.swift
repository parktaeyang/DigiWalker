import DigiWalkerCore
import Foundation
import Testing
@testable import DigiWalker

@MainActor
struct PhoneWidgetPublisherTests {
    final class Reloads: @unchecked Sendable {
        private let lock = NSLock()
        private var kinds: [String] = []
        func add(_ kind: String) { lock.withLock { kinds.append(kind) } }
        var all: [String] { lock.withLock { kinds } }
    }

    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private static let partner = "7770E692-324B-4A27-90EA-437743B4195A"

    private func cache(species: String = "wargreymon", name: String = "워그레이몬", steps: Int = 80_000,
                       receivedAt: Date = t0) throws -> PhoneCache {
        let json = #"{"schemaVersion":4,"revision":5,"createdAt":821692800,"monster":{"id":"\#(Self.partner)","speciesId":"\#(species)","name":"\#(name)","totalCreditedSteps":\#(steps),"distanceMeters":0,"cardId":"agu_ex"},"timeZone":{"identifier":"GMT"},"dex":[{"speciesId":"\#(species)","firstMetAt":821692800,"firstMetSteps":0}],"items":[],"generation":0}"#
        let snapshot = try JSONDecoder().decode(MonsterSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.supersedes(nil))
        return PhoneCache(snapshot: snapshot, receivedAt: receivedAt)
    }

    private func rig(clock: @escaping () -> Date = { t0 }, snapshotURL: URL?? = nil)
        throws -> (PhoneWidgetPublisher, Reloads, URL, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "phone-widget-\(UUID().uuidString)")
        let url = dir.appending(path: WidgetSnapshot.fileName)
        let reloads = Reloads()
        let publisher = PhoneWidgetPublisher(snapshotURL: snapshotURL ?? url, recordURL: dir.appending(path: "record.json"),
                                             reload: reloads.add, now: clock)
        return (publisher, reloads, url, dir)
    }

    @Test func firstPublishWritesAndReloadsOnce() throws {
        let (publisher, reloads, url, dir) = try rig()
        defer { try? FileManager.default.removeItem(at: dir) }
        let value = try cache()
        publisher.publish(value, foreground: false)
        #expect(try StateFile<WidgetSnapshot>(url: url).load()
                == WidgetSnapshot(snapshot: value.snapshot, receivedAt: value.receivedAt))
        #expect(reloads.all == [WidgetSnapshot.widgetKind])
    }

    @Test func identicalCacheIsNeitherWrittenNorReloaded() throws {
        let (publisher, reloads, url, dir) = try rig()
        defer { try? FileManager.default.removeItem(at: dir) }
        let value = try cache()
        publisher.publish(value, foreground: true)
        let written = try Data(contentsOf: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: url.path)
        publisher.publish(value, foreground: true)
        #expect(reloads.all.count == 1)
        #expect(try Data(contentsOf: url) == written)
        let modified = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        #expect(modified == Date(timeIntervalSince1970: 0))
    }

    @Test func foregroundReceiveTimeOnlyChangeIsWrittenAndReloaded() throws {
        let (publisher, reloads, url, dir) = try rig()
        defer { try? FileManager.default.removeItem(at: dir) }
        publisher.publish(try cache(), foreground: true)
        let later = Self.t0.addingTimeInterval(120)
        publisher.publish(try cache(receivedAt: later), foreground: true)
        #expect(try StateFile<WidgetSnapshot>(url: url).load()?.updatedAt == later)
        #expect(reloads.all.count == 2)
    }

    @Test func foregroundFinalStageStepsOnlyChangeStillReloads() throws {
        // sameDisplay ignores steps once a new egg is ready; the foreground rule must not depend on it.
        let (publisher, reloads, url, dir) = try rig()
        defer { try? FileManager.default.removeItem(at: dir) }
        publisher.publish(try cache(steps: 86_000), foreground: true)
        publisher.publish(try cache(steps: 87_000, receivedAt: Self.t0.addingTimeInterval(60)), foreground: true)
        #expect(try StateFile<WidgetSnapshot>(url: url).load()?.totalCreditedSteps == 87_000)
        #expect(reloads.all.count == 2)
    }

    @Test func backgroundStepOnlyChangeIsWrittenNowAndReloadedAfterThirtyMinutes() throws {
        var now = Self.t0
        let (publisher, reloads, url, dir) = try rig(clock: { now })
        defer { try? FileManager.default.removeItem(at: dir) }
        publisher.publish(try cache(steps: 80_000), foreground: false)
        now = Self.t0.addingTimeInterval(10 * 60)
        publisher.publish(try cache(steps: 81_000, receivedAt: now), foreground: false)
        #expect(try StateFile<WidgetSnapshot>(url: url).load()?.totalCreditedSteps == 81_000)
        #expect(reloads.all.count == 1) // held back
        now = Self.t0.addingTimeInterval(31 * 60)
        publisher.publish(try cache(steps: 82_000, receivedAt: now), foreground: false)
        #expect(reloads.all.count == 2)
    }

    @Test func heldBackReloadRunsWhenTheSameCacheIsPublishedInTheForeground() throws {
        var now = Self.t0
        let (publisher, reloads, _, dir) = try rig(clock: { now })
        defer { try? FileManager.default.removeItem(at: dir) }
        publisher.publish(try cache(steps: 80_000), foreground: false)
        now = Self.t0.addingTimeInterval(10 * 60)
        let more = try cache(steps: 81_000, receivedAt: now)
        publisher.publish(more, foreground: false)
        #expect(reloads.all.count == 1) // held back, copy already written
        publisher.publish(more, foreground: true)
        #expect(reloads.all.count == 2)
        publisher.publish(more, foreground: true) // nothing new since that reload
        #expect(reloads.all.count == 2)
    }

    @Test func backgroundReceiveTimeOnlyChangeReloadsOnlyAfterThirtyMinutes() throws {
        var now = Self.t0
        let (publisher, reloads, url, dir) = try rig(clock: { now })
        defer { try? FileManager.default.removeItem(at: dir) }
        publisher.publish(try cache(steps: 86_000), foreground: false) // new egg ready: steps show nowhere
        now = Self.t0.addingTimeInterval(10 * 60)
        publisher.publish(try cache(steps: 86_000, receivedAt: now), foreground: false)
        #expect(try StateFile<WidgetSnapshot>(url: url).load()?.updatedAt == now)
        #expect(reloads.all.count == 1)
        now = Self.t0.addingTimeInterval(31 * 60)
        publisher.publish(try cache(steps: 86_000, receivedAt: now), foreground: false)
        #expect(reloads.all.count == 2)
    }

    @Test func backgroundSpeciesChangeReloadsAtOnce() throws {
        var now = Self.t0
        let (publisher, reloads, _, dir) = try rig(clock: { now })
        defer { try? FileManager.default.removeItem(at: dir) }
        publisher.publish(try cache(), foreground: false)
        now = Self.t0.addingTimeInterval(60)
        publisher.publish(try cache(species: "greymon", name: "그레이몬", receivedAt: now), foreground: false)
        #expect(reloads.all.count == 2)
    }

    @Test func corruptedCopyIsRewrittenAndReloadedEvenWhenTheCacheIsUnchanged() throws {
        let (publisher, reloads, url, dir) = try rig()
        defer { try? FileManager.default.removeItem(at: dir) }
        let value = try cache()
        publisher.publish(value, foreground: false)
        try Data("not json".utf8).write(to: url)
        publisher.publish(value, foreground: false)
        #expect(try StateFile<WidgetSnapshot>(url: url).load()
                == WidgetSnapshot(snapshot: value.snapshot, receivedAt: value.receivedAt))
        #expect(reloads.all.count == 2)
    }

    @Test func recordFromTheFutureDoesNotThrottleAndIsReplaced() throws {
        var now = Self.t0.addingTimeInterval(3_600)
        let (publisher, reloads, _, dir) = try rig(clock: { now })
        defer { try? FileManager.default.removeItem(at: dir) }
        publisher.publish(try cache(steps: 80_000, receivedAt: now), foreground: false)
        now = Self.t0 // the clock was set back an hour
        publisher.publish(try cache(steps: 81_000, receivedAt: now), foreground: false)
        #expect(reloads.all.count == 2)
        now = Self.t0.addingTimeInterval(60) // the new record is the reference again: a step-only change waits
        publisher.publish(try cache(steps: 82_000, receivedAt: now), foreground: false)
        #expect(reloads.all.count == 2)
    }

    @Test func currentCopyWithoutReloadRecordReloadsOnce() throws {
        let (publisher, reloads, _, dir) = try rig()
        defer { try? FileManager.default.removeItem(at: dir) }
        let value = try cache()
        publisher.publish(value, foreground: false)
        try FileManager.default.removeItem(at: dir.appending(path: "record.json"))
        publisher.publish(value, foreground: false)
        #expect(reloads.all.count == 2)
        publisher.publish(value, foreground: false)
        #expect(reloads.all.count == 2)
    }

    @Test func missingContainerDoesNothing() throws {
        let (publisher, reloads, url, dir) = try rig(snapshotURL: .some(nil))
        defer { try? FileManager.default.removeItem(at: dir) }
        publisher.publish(try cache(), foreground: true)
        #expect(reloads.all.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func failedWriteKeepsTheOldCopyAndDoesNotReload() throws {
        let (publisher, reloads, url, dir) = try rig()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        let first = try cache()
        publisher.publish(first, foreground: true)
        let before = try Data(contentsOf: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        publisher.publish(try cache(steps: 81_000, receivedAt: Self.t0.addingTimeInterval(60)), foreground: true)
        #expect(try Data(contentsOf: url) == before)
        #expect(reloads.all.count == 1)
    }
}
