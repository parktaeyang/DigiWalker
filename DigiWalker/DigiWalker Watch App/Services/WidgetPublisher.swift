import DigiWalkerCore
import Foundation
import WidgetKit

/// Writes the display copy for the watch face complication. Never throws: a failed copy must not touch
/// settlement, the game file or notifications.
protocol WidgetPublishing {
    func publish(_ snapshot: WidgetSnapshot, foreground: Bool)
}

/// Writes `widget-snapshot.json` into the App Group container and asks WidgetKit to reload when
/// `WidgetReloadPolicy` says so. The last reload is kept in the app's own container, so a step-only change that
/// was held back is still reloaded by a later settlement, even in a freshly launched background process.
final class WidgetPublisher: WidgetPublishing {
    private let snapshotFile: StateFile<WidgetSnapshot>?
    private let recordFile: StateFile<WidgetReloadRecord>
    private let reload: (String) -> Void
    private let now: () -> Date

    init(
        snapshotURL: URL? = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroupIdentifier)?
            .appending(path: WidgetSnapshot.fileName),
        recordURL: URL = URL.applicationSupportDirectory.appending(path: "widget-reload.json"),
        reload: @escaping (String) -> Void = { WidgetCenter.shared.reloadTimelines(ofKind: $0) },
        now: @escaping () -> Date = { .now }
    ) {
        snapshotFile = snapshotURL.map { StateFile(url: $0) }
        recordFile = StateFile(url: recordURL)
        self.reload = reload
        self.now = now
    }

    func publish(_ snapshot: WidgetSnapshot, foreground: Bool) {
        guard let snapshotFile else {
            NSLog("DigiWalker: widget container unavailable")
            return
        }
        // A missing, unreadable or unsupported-version copy is rewritten and always reloaded, even if nothing else changed.
        let readable = (try? snapshotFile.load()) ?? nil
        let current = readable.flatMap { WidgetSnapshot.supportedSchemaVersions.contains($0.schemaVersion) ? $0 : nil }
        let rewritten = current?.sameDisplay(as: snapshot) != true
        if rewritten {
            do { try snapshotFile.save(snapshot) } catch {
                NSLog("DigiWalker: widget copy not saved (%@)", error.localizedDescription)
                return
            }
        }
        let record = (try? recordFile.load()) ?? nil
        let time = now()
        let previous = current == nil ? nil : record?.snapshot
        guard WidgetReloadPolicy.shouldReload(
            previous: previous, next: snapshot, foreground: foreground, lastReload: record?.at, now: time
        ) else { return }
        reload(WidgetSnapshot.widgetKind)
        do { try recordFile.save(WidgetReloadRecord(snapshot: snapshot, at: time)) } catch {
            NSLog("DigiWalker: widget reload record not saved (%@)", error.localizedDescription)
        }
    }
}

struct InertWidgetPublisher: WidgetPublishing {
    func publish(_ snapshot: WidgetSnapshot, foreground: Bool) {}
}
