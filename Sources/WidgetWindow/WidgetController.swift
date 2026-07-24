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

        panel.setFrame(frame, display: true)
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
        return created
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
    private func reconcilePanelsForScreenChange() {
        let fallback = NSScreen.main?.visibleFrame ?? .zero
        let screens = currentScreenFrames()
        for kind in open {
            guard let panel = panels[kind] else { continue }
            let clamped = WidgetPlacement.clamped(frame: panel.frame, screens: screens, fallback: fallback)
            if clamped != panel.frame {
                panel.setFrame(clamped, display: true)
                persistence.setFrame(clamped, for: kind)
            }
        }
    }

    private func currentScreenFrames() -> [CGRect] {
        NSScreen.screens.map(\.visibleFrame)
    }
}
