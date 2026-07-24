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
    @Published private(set) var open: Set<WidgetKind> = []

    private var panels: [WidgetKind: WidgetPanel] = [:]
    private let persistence: WidgetPersistence
    private var screenParamsObserver: NSObjectProtocol?

    /// Placeholder intrinsic size used only for `WidgetPlacement.defaultFrame`
    /// when a widget has no remembered frame yet. The real per-widget sizing
    /// arrives with the widget views themselves.
    private let defaultSize = CGSize(width: 320, height: 400)

    /// Supplies the SwiftUI content for a widget when it's shown. Left
    /// unset here deliberately — this file has no dependency on any widget
    /// view; the next step wires real views in.
    var contentProvider: ((WidgetKind) -> AnyView)?

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
            panel.setContent(provider(kind))
        }

        let fallback = NSScreen.main?.visibleFrame ?? .zero
        let target = persistence.frame(for: kind) ?? WidgetPlacement.defaultFrame(size: defaultSize, on: fallback)
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
        panel.orderOut(nil)

        open.remove(kind)
        persistence.openSet = open
    }

    /// Returns the panel for `kind`, lazily creating and storing one if
    /// needed.
    private func panel(for kind: WidgetKind) -> WidgetPanel {
        if let existing = panels[kind] { return existing }
        let created = WidgetPanel(kind: kind)
        panels[kind] = created
        return created
    }

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
