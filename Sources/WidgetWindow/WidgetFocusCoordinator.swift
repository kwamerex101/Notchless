import AppKit

/// A panel that can borrow keyboard focus from the app's shared
/// non-activating-panel focus mechanism (see `NotchPanel.wantsKey`,
/// `WidgetPanel.wantsKey`).
@MainActor protocol KeyBorrowingPanel: AnyObject {
    var wantsKey: Bool { get set }
    func makeKeyAndOrderFront(_ sender: Any?)
}

extension NotchPanel: KeyBorrowingPanel {}

/// Mediates keyboard focus across every panel that can borrow it (the notch
/// plus any number of open widgets).
///
/// The single-panel version of this — `AppDelegate`'s `requestKeyFocus`
/// closure — activates the app and calls `makeKeyAndOrderFront` on `want`,
/// and calls `NSApp.deactivate()` on release. That breaks with more than one
/// panel: moving focus from panel A's text field to panel B's fires A's
/// release first, which calls `NSApp.deactivate()` while B is mid-transfer
/// trying to become key. This coordinator tracks a single current holder and
/// transfers focus directly between panels without ever deactivating in
/// between, deactivating only once nothing wants key.
@MainActor final class WidgetFocusCoordinator {
    /// Injected so the coordinator's transfer logic is testable without
    /// touching the real `NSApp`.
    var activate: () -> Void = { NSApp.activate(ignoringOtherApps: true) }
    var deactivate: () -> Void = { NSApp.deactivate() }

    private weak var holder: KeyBorrowingPanel?
    private var pendingRelease: DispatchWorkItem?

    /// Whether a deactivate is currently scheduled (exposed for tests).
    private(set) var hasPendingRelease: Bool = false

    /// Gives `panel` the key-focus borrow. If `panel` already holds it, does
    /// nothing. Otherwise clears the previous holder's `wantsKey`, cancels
    /// any pending deactivate (this is the transfer case: a following borrow
    /// preempts a scheduled release with no deactivate/reactivate flicker),
    /// and activates + makes `panel` key.
    func borrow(_ panel: KeyBorrowingPanel) {
        if holder === panel { return }

        pendingRelease?.cancel()
        pendingRelease = nil
        hasPendingRelease = false

        holder?.wantsKey = false

        panel.wantsKey = true
        holder = panel
        activate()
        panel.makeKeyAndOrderFront(nil)
    }

    /// Releases `panel`'s borrow. A stale release from a panel that isn't
    /// the current holder (e.g. it already lost focus to another panel) is
    /// ignored and must not deactivate the app. Otherwise clears
    /// `wantsKey`, drops the holder, and schedules `deactivate()` on the
    /// next runloop turn rather than calling it inline, so an immediately
    /// following `borrow` can cancel it.
    func release(_ panel: KeyBorrowingPanel) {
        guard holder === panel else { return }

        panel.wantsKey = false
        holder = nil

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hasPendingRelease = false
            self.pendingRelease = nil
            self.deactivate()
        }
        pendingRelease = work
        hasPendingRelease = true
        DispatchQueue.main.async(execute: work)
    }
}
