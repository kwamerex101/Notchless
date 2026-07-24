import AppKit
import SwiftUI

/// Owns the set of open section widgets and the `WidgetPanel` backing each
/// one. Persists open/closed state and per-widget frames locally (see
/// `WidgetPersistence`), and keeps every open panel on a live screen as
/// displays connect/disconnect, mirroring `HUDPresenter`'s
/// `didChangeScreenParametersNotification` handling.
///
/// Has no dependency on any widget's SwiftUI view — callers supply content
/// through `contentProvider`. Until that's wired up, `show(_:)` opens an
/// empty panel.
@MainActor final class WidgetController: ObservableObject {
    /// Reached the same way `TodoStore`/`GoalStore` are — a singleton — so
    /// SwiftUI views deep in the notch hierarchy (the pop-out buttons) can
    /// read/toggle open state without a dependency-injection seam of their
    /// own.
    static let shared = WidgetController()

    @Published private(set) var open: Set<WidgetKind> = []

    private var panels: [WidgetKind: WidgetPanel] = [:]
    private let persistence: WidgetPersistence
    private var screenParamsObserver: NSObjectProtocol?

    /// Per-panel `NSWindow.didMoveNotification` observers backing the
    /// drag-persists-position fix (bug 3) — one per panel, added once when
    /// the panel is created and removed in `deinit`.
    private var moveObservers: [WidgetKind: NSObjectProtocol] = [:]

    /// Coalesces the burst of `didMove` notifications a single drag emits
    /// into one persisted write, per widget.
    private var pendingMovePersists: [WidgetKind: DispatchWorkItem] = [:]

    /// How long to wait after the last `didMove` in a burst before
    /// persisting. A drag fires many of these per second; without
    /// coalescing every intermediate frame would hit `UserDefaults`.
    private static let movePersistDebounce: TimeInterval = 0.2

    /// True while this controller is moving a panel programmatically (a
    /// screen-reconcile rescue, or the `setFrame` in `show`/`restore`) —
    /// distinguishes that from a user drag so the `didMove` observer above
    /// doesn't treat it as a position to remember (bug 4: a rescue must be
    /// ephemeral, and `show`/`restore` already persist explicitly, so
    /// letting `didMove` persist too would just be redundant work).
    private var isApplyingProgrammaticFrame = false

    /// Default intrinsic size used for `WidgetPlacement.defaultFrame` when a
    /// widget has no remembered frame yet, sized to what each widget's real
    /// SwiftUI content needs. `.meeting` has no view yet (phase 3) so it
    /// keeps a nominal placeholder — nothing opens it today.
    private func defaultSize(for kind: WidgetKind) -> CGSize {
        switch kind {
        case .todos:   return CGSize(width: 340, height: 440)
        case .goals:   return CGSize(width: 360, height: 460)
        case .meeting: return CGSize(width: 320, height: 400)
        }
    }

    /// Supplies the SwiftUI content for a widget when it's shown, given the
    /// panel it will be hosted in — callers need the panel to wire that
    /// widget's own key-focus borrow/release (see `WidgetFocusCoordinator`).
    var contentProvider: ((WidgetKind, WidgetPanel) -> AnyView)?

    /// Handed to every panel this controller creates, so each one can borrow
    /// key focus on click and release it on resign-key (see
    /// `WidgetPanel.mouseDown`/`resignKey`). `AppDelegate` sets this once,
    /// before restoring any previously-open widgets.
    weak var focusCoordinator: WidgetFocusCoordinator?

    /// Test seam: how the controller discovers live screens, as frames.
    /// Defaults to the real `NSScreen.screens`. `NSScreen` has no public
    /// initializer, so tests fake screens as plain `CGRect`s here rather
    /// than constructing real `NSScreen`s — including the empty-array case
    /// bug 2 guards against, which can't otherwise be produced on demand
    /// from a live test run's real screens.
    var screenFramesProvider: () -> [CGRect] = { NSScreen.screens.map(\.visibleFrame) }

    init(defaults: UserDefaults = .standard) {
        persistence = WidgetPersistence(defaults: defaults)
        open = persistence.openSet

        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reconcilePanelsForScreenChange() }
        }
    }

    deinit {
        if let screenParamsObserver {
            NotificationCenter.default.removeObserver(screenParamsObserver)
        }
        for (_, observer) in moveObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        for (_, work) in pendingMovePersists {
            work.cancel()
        }
    }

    func isOpen(_ kind: WidgetKind) -> Bool { open.contains(kind) }

    func toggle(_ kind: WidgetKind) {
        if isOpen(kind) {
            close(kind)
        } else {
            show(kind)
        }
    }

    /// Opens (or brings forward) the widget for `kind`, restoring its
    /// remembered frame — clamped onto a live screen — or falling back to a
    /// default frame on the main screen.
    func show(_ kind: WidgetKind) {
        let panel = panel(for: kind)
        if let provider = contentProvider {
            panel.setContent(provider(kind, panel))
        }

        let fallback = NSScreen.main?.visibleFrame ?? .zero
        let target = persistence.frame(for: kind) ?? WidgetPlacement.defaultFrame(size: defaultSize(for: kind), on: fallback)
        let frame = WidgetPlacement.clamped(frame: target, screens: currentScreenFrames(), fallback: fallback)

        // Suppress the didMove-triggered persist below: this frame is about
        // to be persisted explicitly, right after, with the exact same
        // value — letting didMove persist too would just be a redundant
        // scheduled write.
        isApplyingProgrammaticFrame = true
        panel.setFrame(frame, display: true)
        isApplyingProgrammaticFrame = false
        panel.orderFrontRegardless()
        persistence.setFrame(frame, for: kind)

        open.insert(kind)
        persistence.openSet = open
    }

    func close(_ kind: WidgetKind) {
        guard let panel = panels[kind] else { return }
        persistence.setFrame(panel.frame, for: kind)
        // Release before ordering out: a panel closed while it still holds
        // the borrow would otherwise leave the app activated with no
        // holder — nothing left to hand focus back on resign-key, since the
        // panel is gone.
        focusCoordinator?.release(panel)
        panel.orderOut(nil)

        open.remove(kind)
        persistence.openSet = open
    }

    /// Returns the panel for `kind`, lazily creating and storing one if
    /// needed.
    private func panel(for kind: WidgetKind) -> WidgetPanel {
        if let existing = panels[kind] { return existing }
        let created = WidgetPanel(kind: kind)
        created.focusCoordinator = focusCoordinator
        panels[kind] = created
        moveObservers[kind] = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: created,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleMovePersist(for: kind, panel: created)
        }
        return created
    }

    /// Debounced `didMove` handler backing bug 3 (persist a drag's landing
    /// spot) while staying out of bug 4's way (never persist a rescue).
    /// Ignored entirely while `isApplyingProgrammaticFrame` is set — only a
    /// real user drag should end up here.
    private func scheduleMovePersist(for kind: WidgetKind, panel: WidgetPanel) {
        guard !isApplyingProgrammaticFrame else { return }
        pendingMovePersists[kind]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persistence.setFrame(panel.frame, for: kind)
        }
        pendingMovePersists[kind] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.movePersistDebounce, execute: work)
    }

    /// Test seam: exposes the backing panel for an already-open widget.
    /// Production code never needs a panel reference directly — it goes
    /// through `show`/`close`/`toggle` — but tests exercising the
    /// coordinator handoff (e.g. close-while-holding) need one to borrow
    /// against.
    func existingPanel(for kind: WidgetKind) -> WidgetPanel? { panels[kind] }

    /// Reopens every widget the persisted open set records, clamping each
    /// remembered frame onto a live screen. Call once at launch.
    func restore() {
        for kind in persistence.openSet {
            show(kind)
        }
    }

    /// `NSApplication.didChangeScreenParametersNotification` handler:
    /// re-clamps every open panel's frame back onto a live screen. A widget
    /// parked on a display that disconnects would otherwise sit at
    /// coordinates on no screen at all, unreachable, with its close button
    /// unclickable.
    ///
    /// Two guards keep this from doing more harm than good:
    ///
    /// - `NSScreen.screens` can be transiently empty mid display
    ///   reconfiguration (sleep/wake, clamshell). Reconciling against that
    ///   would treat every screen as disconnected and rescue every open
    ///   widget onto a `.zero` fallback for no reason — bail out instead and
    ///   let the next, real notification do the reconciling.
    /// - A rescue here is ephemeral: it moves the panel so the widget stays
    ///   reachable right now, but must NOT overwrite the user's remembered
    ///   frame (bug 4) — an external display blinking out for a moment
    ///   would otherwise permanently teleport the widget to the built-in
    ///   screen, even after the display returns. `isApplyingProgrammaticFrame`
    ///   also keeps the `didMove` persist (bug 3) from re-persisting this
    ///   rescued position under our feet.
    ///
    /// Not `private`: also a test seam. Production code only reaches this
    /// through the `didChangeScreenParametersNotification` observer set up
    /// in `init` — real screen changes can't be produced on demand in a
    /// test run, so tests call this directly after pointing
    /// `screenFramesProvider` at a synthetic screen layout.
    func reconcilePanelsForScreenChange() {
        let screens = currentScreenFrames()
        guard !screens.isEmpty else { return }

        let fallback = NSScreen.main?.visibleFrame ?? .zero
        isApplyingProgrammaticFrame = true
        defer { isApplyingProgrammaticFrame = false }
        for kind in open {
            guard let panel = panels[kind] else { continue }
            let clamped = WidgetPlacement.clamped(frame: panel.frame, screens: screens, fallback: fallback)
            if clamped != panel.frame {
                panel.setFrame(clamped, display: true)
            }
        }
    }

    private func currentScreenFrames() -> [CGRect] {
        screenFramesProvider()
    }
}
