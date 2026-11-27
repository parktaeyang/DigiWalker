import DigiWalkerCore
import Foundation

/// Which of the growth alert and the "start a new egg?" dialog may be on screen. They never overlap: the alert
/// shows only while no dialog is wanted, the dialog only while no alert is shown or closing.
struct AlertFlow {
    /// The event the alert is showing. Tracked here so the next queued event gets a fresh presentation.
    private(set) var presented: GrowthEvent?
    /// True from closing an alert until the pause before the next step ends. Neither alert nor dialog shows then.
    private(set) var closing = false

    var dialogMayShow: Bool { presented == nil && !closing }

    /// Presents `next` if nothing is showing, nothing is closing and no dialog is wanted.
    mutating func present(_ next: GrowthEvent?, dialogWanted: Bool) {
        guard presented == nil, !closing, !dialogWanted, let next else { return }
        presented = next
    }

    /// Returns the event that was showing, to be dismissed in the queue. Starts the closing pause.
    mutating func close() -> GrowthEvent? {
        guard let shown = presented else { return nil }
        closing = true
        presented = nil
        return shown
    }

    /// The closing pause is over. A wanted dialog opens now (the view derives that from `dialogMayShow`), so it
    /// takes the place of the next alert; otherwise the next queued event is presented.
    mutating func pauseEnded(next: GrowthEvent?, dialogWanted: Bool) {
        closing = false
        present(next, dialogWanted: dialogWanted)
    }

    /// An offer that left the queue (its egg was started elsewhere, e.g. by the iPhone) must not stay on screen.
    /// Returns true if it was dropped.
    @discardableResult
    mutating func dropOfferIfGone(from queue: [GrowthEvent]) -> Bool {
        guard let shown = presented, shown.kind == .newEggReady, !queue.contains(where: { $0.id == shown.id }) else { return false }
        presented = nil
        return true
    }
}
