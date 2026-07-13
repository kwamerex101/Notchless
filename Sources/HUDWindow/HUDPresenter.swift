import AppKit
import SwiftUI

/// The sole sink `HUDController` shows HUDs through. Routes to the notch
/// (`model.showHUD`, unchanged behavior) when `hudStyle == .notch`, or to a
/// non-interactive floating panel — sized and styled per `hudStyle`,
/// positioned at `hudPosition` — otherwise. On the floating route it leaves
/// `model.hud == nil` so the notch does not also morph into a HUD
/// (`NotchViewModel.content` resolves `hud` first).
@MainActor
final class HUDPresenter {
    private let model: NotchViewModel
    private let panel = FloatingHUDPanel()
    private var hideWork: DispatchWorkItem?

    /// All-displays mode (P5b): one panel per screen, keyed by display id.
    /// Populated/torn down lazily only while `model.settings.hudAllDisplays`
    /// is on; the single-display path above never touches this dict.
    private var panels: [CGDirectDisplayID: FloatingHUDPanel] = [:]
    private var screenParamsObserver: NSObjectProtocol?

    /// Set by `HUDController` to drive the live system setter (volume or
    /// brightness) when the user click-drags the floating HUD (Phase 5).
    var applyValue: ((HUDKind, Double) -> Void)?

    init(model: NotchViewModel) {
        self.model = model
        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reconcilePanelsForScreenChange()
        }
    }

    deinit {
        if let screenParamsObserver {
            NotificationCenter.default.removeObserver(screenParamsObserver)
        }
    }

    /// Pure route selection: `.notch` is the only style the notch itself
    /// renders; every other `HUDStyle` routes to the floating panel.
    nonisolated static func isNotchRoute(_ style: HUDStyle) -> Bool {
        style == .notch
    }

    /// The display id whose frame contains `point` (mouse location), or nil
    /// if none of `frames` contains it. Used to decide which all-displays
    /// panel is interactive (the one under the cursor).
    nonisolated static func screenID(containing point: CGPoint,
                                      in frames: [(id: CGDirectDisplayID, frame: NSRect)]) -> CGDirectDisplayID? {
        frames.first { $0.frame.contains(point) }?.id
    }

    /// Panel keys to tear down: those `existing` but no longer among
    /// `current` screens. Never removes a still-present screen.
    nonisolated static func panelsToRemove(existing: Set<CGDirectDisplayID>,
                                            current: Set<CGDirectDisplayID>) -> Set<CGDirectDisplayID> {
        existing.subtracting(current)
    }

    func show(_ kind: HUDKind) {
        let style = model.settings.hudStyle
        if Self.isNotchRoute(style) {
            hide()
            model.showHUD(kind)
            return
        }

        model.hideHUD()

        if model.settings.hudAllDisplays {
            showAllDisplays(kind, style: style)
        } else {
            showSingleDisplay(kind, style: style)
        }

        scheduleHide()
    }

    private func showSingleDisplay(_ kind: HUDKind, style: HUDStyle) {
        let options = HUDOptions(from: model.settings)
        let accent = model.settings.hudUseAccentColor ? model.artworkColor : nil
        let interactive = model.settings.clickDragToChangeValue
        panel.ignoresMouseEvents = !interactive

        let onDragFraction: ((Double, Bool) -> Void)? = interactive
            ? { [weak self] fraction, isEnded in
                self?.handleDrag(baseKind: kind, fraction: fraction, isEnded: isEnded,
                                  style: style, options: options, accent: accent, targetPanel: self?.panel)
              }
            : nil

        panel.setContent(FloatingHUDContentView(
            kind: kind,
            options: options,
            style: style,
            indicator: model.settings.hudIndicator,
            accent: accent,
            onDragFraction: onDragFraction
        ))

        let frame = FloatingHUDPositioner.frame(
            for: model.settings.hudPosition,
            hudSize: FloatingHUDContentView.estimatedSize(for: style),
            in: NSScreen.main?.visibleFrame ?? .zero,
            inset: 16
        )
        panel.show(at: frame)
    }

    /// All-displays mode: one panel per current `NSScreen`, positioned in
    /// each screen's `visibleFrame`. Only the panel on the cursor's screen
    /// is interactive for click-drag; the rest ignore mouse events. Stale
    /// panels (for screens no longer present) are torn down afterward.
    private func showAllDisplays(_ kind: HUDKind, style: HUDStyle) {
        let options = HUDOptions(from: model.settings)
        let accent = model.settings.hudUseAccentColor ? model.artworkColor : nil
        let interactive = model.settings.clickDragToChangeValue

        let screens = NSScreen.screens.compactMap { screen -> (id: CGDirectDisplayID, screen: NSScreen)? in
            guard let id = screen.displayID else { return nil }
            return (id, screen)
        }
        let cursorScreenID = interactive
            ? Self.screenID(containing: NSEvent.mouseLocation, in: screens.map { ($0.id, $0.screen.frame) })
            : nil

        for (id, screen) in screens {
            let hudPanel = panel(for: id)
            let isInteractive = interactive && id == cursorScreenID
            hudPanel.ignoresMouseEvents = !isInteractive

            let onDragFraction: ((Double, Bool) -> Void)? = isInteractive
                ? { [weak self, weak hudPanel] fraction, isEnded in
                    self?.handleDrag(baseKind: kind, fraction: fraction, isEnded: isEnded,
                                      style: style, options: options, accent: accent, targetPanel: hudPanel)
                  }
                : nil

            hudPanel.setContent(FloatingHUDContentView(
                kind: kind,
                options: options,
                style: style,
                indicator: model.settings.hudIndicator,
                accent: accent,
                onDragFraction: onDragFraction
            ))

            let frame = FloatingHUDPositioner.frame(
                for: model.settings.hudPosition,
                hudSize: FloatingHUDContentView.estimatedSize(for: style),
                in: screen.visibleFrame,
                inset: 16
            )
            hudPanel.show(at: frame)
        }

        removeStalePanels(current: Set(screens.map(\.id)))
    }

    /// Returns the panel for `id`, lazily creating and storing one if needed.
    private func panel(for id: CGDirectDisplayID) -> FloatingHUDPanel {
        if let existing = panels[id] { return existing }
        let created = FloatingHUDPanel()
        panels[id] = created
        return created
    }

    /// Hides and drops any tracked panel whose display id is not in `current`.
    private func removeStalePanels(current: Set<CGDirectDisplayID>) {
        let stale = Self.panelsToRemove(existing: Set(panels.keys), current: current)
        for id in stale {
            panels[id]?.hide()
            panels.removeValue(forKey: id)
        }
    }

    /// `NSApplication.didChangeScreenParametersNotification` handler: drops
    /// panels for screens that disappeared (external display unplugged,
    /// resolution/arrangement change). Remaining panels rebuild lazily on
    /// the next `show`.
    private func reconcilePanelsForScreenChange() {
        let currentIDs = Set(NSScreen.screens.compactMap(\.displayID))
        removeStalePanels(current: currentIDs)
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        panel.hide()
        for hudPanel in panels.values {
            hudPanel.hide()
        }
    }

    /// Live-updates the floating panel while the user click-drags it
    /// (Phase 5, `clickDragToChangeValue`). Rebuilds `kind` with the dragged
    /// fraction (preserving e.g. `muted` on `.sound`), drives the system
    /// setter via `applyValue`, and re-renders the panel content in place
    /// (`FloatingHUDPanel.setContent` never repositions the panel). Auto-hide
    /// is suspended for the duration of the drag and rescheduled once it ends.
    ///
    /// `targetPanel` is the specific panel driving the gesture (`panel` on
    /// the single-display path, or the cursor-screen panel in all-displays
    /// mode). Only that panel updates live; in all-displays mode the other
    /// screens' panels are not touched mid-drag and simply refresh with the
    /// final value on the next `show` (see P5b report for rationale).
    private func handleDrag(baseKind: HUDKind, fraction: Double, isEnded: Bool,
                             style: HUDStyle, options: HUDOptions, accent: Color?,
                             targetPanel: FloatingHUDPanel?) {
        hideWork?.cancel()

        let updatedKind = Self.updatedKind(baseKind, value: fraction)
        applyValue?(updatedKind, fraction)

        targetPanel?.setContent(FloatingHUDContentView(
            kind: updatedKind,
            options: options,
            style: style,
            indicator: model.settings.hudIndicator,
            accent: accent,
            onDragFraction: { [weak self, weak targetPanel] nextFraction, nextIsEnded in
                self?.handleDrag(baseKind: updatedKind, fraction: nextFraction, isEnded: nextIsEnded,
                                  style: style, options: options, accent: accent, targetPanel: targetPanel)
            }
        ))

        if isEnded {
            scheduleHide()
        }
    }

    /// Rebuilds `kind` with `value` substituted in for its level, preserving
    /// any other associated state (e.g. `.sound`'s `muted`).
    private static func updatedKind(_ kind: HUDKind, value: Double) -> HUDKind {
        switch kind {
        case let .sound(_, muted):
            return .sound(level: value, muted: muted)
        case .display:
            return .display(level: value)
        }
    }

    private func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        let delay = NotchViewModel.clampHUDDelay(model.settings.hudHideDelay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

extension NSScreen {
    /// The `CGDirectDisplayID` backing this screen, used to key all-displays
    /// HUD panels per physical screen.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
