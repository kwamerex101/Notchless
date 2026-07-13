import AppKit

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
        panel.setContent(FloatingHUDContentView(
            kind: kind,
            options: options,
            style: style,
            indicator: model.settings.hudIndicator,
            accent: accent
        ))

        let frame = FloatingHUDPositioner.frame(
            for: model.settings.hudPosition,
            hudSize: FloatingHUDContentView.estimatedSize(for: style),
            in: NSScreen.main?.visibleFrame ?? .zero,
            inset: 16
        )
        panel.show(at: frame)

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        let delay = NotchViewModel.clampHUDDelay(model.settings.hudHideDelay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        panel.hide()
    }
}
