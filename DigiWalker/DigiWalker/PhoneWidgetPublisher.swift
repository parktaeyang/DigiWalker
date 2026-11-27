import DigiWalkerCore
import Foundation
import WidgetKit

/// Writes the display copy for the iPhone widget. Never throws: a failed copy must not touch the watch cache,
/// the status line or a new egg request.
protocol PhoneWidgetPublishing {
    func publish(_ cache: PhoneCache, foreground: Bool)
}

/// Writes `widget-snapshot.json` into the iPhone's App Group container and asks WidgetKit to reload. The copy is
/// rewritten whenever it differs at all from the last one (the small widget shows the receive time). Whether to
/// reload is judged against the last reload (kept in the app's own container, so a held-back change is picked up by
/// a later publish even if the file is already current): in the foreground anything changed since then reloads; in
/// the background `WidgetReloadPolicy` decides, plus a newer receive time once the step-only interval has passed.
final class PhoneWidgetPublisher: PhoneWidgetPublishing {
    private let snapshotFile: StateFile<WidgetSnapshot>?
    private let recordFile: StateFile<WidgetReloadRecord>
    private let reload: (String) -> Void
    private let now: () -> Date

    init(
        snapshotURL: URL? = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroupIdentifier)?
            .appending(path: WidgetSnapshot.fileName),
        recordURL: URL = URL.applicationSupportDirectory.appending(path: "phone-widget-reload.json"),
        reload: @escaping (String) -> Void = { WidgetCenter.shared.reloadTimelines(ofKind: $0) },
        now: @escaping () -> Date = { .now }
    ) {
        snapshotFile = snapshotURL.map { StateFile(url: $0) }
        recordFile = StateFile(url: recordURL)
        self.reload = reload
        self.now = now
    }

    /// Foreground: any change since the last reload reloads (reloads requested by the foreground app are not
    /// budgeted, and it keeps the receive time current). Background: what `WidgetReloadPolicy` allows, plus a newer
    /// receive time once the step-only interval has passed (the small widget shows it even when nothing else changed).
    static func shouldReload(
        previous: WidgetSnapshot?, next: WidgetSnapshot, foreground: Bool, lastReload: Date?, now: Date
    ) -> Bool {
        if foreground { return true }
        // A record from the future (the clock was set back) cannot throttle anything: reload once and start over.
        if let lastReload, lastReload > now { return true }
        if WidgetReloadPolicy.shouldReload(previous: previous, next: next, foreground: false,
                                           lastReload: lastReload, now: now) { return true }
        guard let previous, let lastReload else { return false }
        return next.updatedAt > previous.updatedAt
            && now.timeIntervalSince(lastReload) >= WidgetReloadPolicy.stepOnlyInterval
    }

    func publish(_ cache: PhoneCache, foreground: Bool) {
        guard let snapshotFile else {
            NSLog("DigiWalker: phone widget container unavailable")
            return
        }
        let next = WidgetSnapshot(snapshot: cache.snapshot, receivedAt: cache.receivedAt)
        // A missing, unreadable or unsupported-version copy is rewritten and always reloaded.
        let readable = (try? snapshotFile.load()) ?? nil
        let current = readable.flatMap { WidgetSnapshot.supportedSchemaVersions.contains($0.schemaVersion) ? $0 : nil }
        if current != next {
            do { try snapshotFile.save(next) } catch {
                NSLog("DigiWalker: phone widget copy not saved (%@)", error.localizedDescription)
                return
            }
        }
        // Evaluated even when the file was already current: an earlier background publish may have held the reload back.
        let record = (try? recordFile.load()) ?? nil
        let previous = current == nil ? nil : record?.snapshot
        if previous == next { return } // this exact copy was already reloaded
        let time = now()
        guard Self.shouldReload(previous: previous, next: next, foreground: foreground,
                                lastReload: record?.at, now: time) else { return }
        reload(WidgetSnapshot.widgetKind)
        // If the record cannot be saved, the next publish sees an older record and reloads again. That leans toward
        // a redundant reload rather than a stale widget, which is intended.
        do { try recordFile.save(WidgetReloadRecord(snapshot: next, at: time)) } catch {
            NSLog("DigiWalker: phone widget reload record not saved (%@)", error.localizedDescription)
        }
    }
}

struct InertPhoneWidgetPublisher: PhoneWidgetPublishing {
    func publish(_ cache: PhoneCache, foreground: Bool) {}
}
