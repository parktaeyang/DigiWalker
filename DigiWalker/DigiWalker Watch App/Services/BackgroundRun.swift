import Foundation

/// Runs background work and calls `complete` exactly once: when the work ends (normally or by throwing)
/// or when `timeout` passes, whichever comes first. A timeout does not cancel the work; settlements save
/// atomically and finish whenever the system lets the process run again.
enum BackgroundRun {
    @MainActor
    private final class Once {
        private var complete: (() -> Void)?
        init(_ complete: @escaping () -> Void) { self.complete = complete }
        func fire() {
            let call = complete
            complete = nil
            call?()
        }
    }

    /// Returns a closure that completes early (e.g. from an expiration handler) through the same one-time path.
    @discardableResult
    @MainActor
    static func run(
        timeout: Duration = .seconds(20),
        work: @escaping () async throws -> Void,
        complete: @escaping () -> Void
    ) -> @MainActor @Sendable () -> Void {
        let once = Once(complete)
        let timer = Task {
            try? await Task.sleep(for: timeout)
            once.fire()
        }
        Task {
            do { try await work() } catch { NSLog("DigiWalker: background work failed (%@)", error.localizedDescription) }
            timer.cancel()
            once.fire()
        }
        return { once.fire() }
    }
}
