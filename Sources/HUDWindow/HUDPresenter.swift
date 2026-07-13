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

    /// Set by `HUDController` to drive the live system setter (volume or
    /// brightness) when the user click-drags the floating HUD (Phase 5).
    var applyValue: ((HUDKind, Double) -> Void)?

    init(model: NotchViewModel) {
        self.model = model
    }

    /// Pure route selection: `.notch` is the only style the notch itself
    /// renders; every other `HUDStyle` routes to the floating panel.
    nonisolated static func isNotchRoute(_ style: HUDStyle) -> Bool {
        style == .notch
    }

    func show(_ kind: HUDKind) {
        let style = model.settings.hudStyle
        if Self.isNotchRoute(style) {
            hide()
            model.showHUD(kind)
            return
        }

        model.hideHUD()

        let options = HUDOptions(from: model.settings)
        let accent = model.settings.hudUseAccentColor ? model.artworkColor : nil
        let interactive = model.settings.clickDragToChangeValue
        panel.ignoresMouseEvents = !interactive

        let onDragFraction: ((Double, Bool) -> Void)? = interactive
            ? { [weak self] fraction, isEnded in
                self?.handleDrag(baseKind: kind, fraction: fraction, isEnded: isEnded,
                                  style: style, options: options, accent: accent)
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

        scheduleHide()
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        panel.hide()
    }

    /// Live-updates the floating panel while the user click-drags it
    /// (Phase 5, `clickDragToChangeValue`). Rebuilds `kind` with the dragged
    /// fraction (preserving e.g. `muted` on `.sound`), drives the system
    /// setter via `applyValue`, and re-renders the panel content in place
    /// (`FloatingHUDPanel.setContent` never repositions the panel). Auto-hide
    /// is suspended for the duration of the drag and rescheduled once it ends.
    private func handleDrag(baseKind: HUDKind, fraction: Double, isEnded: Bool,
                             style: HUDStyle, options: HUDOptions, accent: Color?) {
        hideWork?.cancel()

        let updatedKind = Self.updatedKind(baseKind, value: fraction)
        applyValue?(updatedKind, fraction)

        panel.setContent(FloatingHUDContentView(
            kind: updatedKind,
            options: options,
            style: style,
            indicator: model.settings.hudIndicator,
            accent: accent,
            onDragFraction: { [weak self] nextFraction, nextIsEnded in
                self?.handleDrag(baseKind: updatedKind, fraction: nextFraction, isEnded: nextIsEnded,
                                  style: style, options: options, accent: accent)
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
