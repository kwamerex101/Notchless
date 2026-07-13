import AppKit

/// The sole sink `HUDController` shows HUDs through. Routes to the notch
/// (`model.showHUD`, unchanged behavior) when `hudPosition == .top`, or to a
/// non-interactive floating panel otherwise — and on the floating route
/// leaves `model.hud == nil` so the notch does not also morph into a HUD
/// (`NotchViewModel.content` resolves `hud` first).
@MainActor
final class HUDPresenter {
    private let model: NotchViewModel
    private let panel = FloatingHUDPanel()
    private var hideWork: DispatchWorkItem?

    init(model: NotchViewModel) {
        self.model = model
    }

    /// Pure route selection: `.top` is the notch's home position; every
    /// other `HUDPosition` routes to the floating panel.
    nonisolated static func isNotchRoute(_ position: HUDPosition) -> Bool {
        position == .top
    }

    func show(_ kind: HUDKind) {
        let position = model.settings.hudPosition
        if Self.isNotchRoute(position) {
            hide()
            model.showHUD(kind)
            return
        }

        model.hideHUD()

        let options = HUDOptions(from: model.settings)
        panel.setContent(FloatingHUDContentView(kind: kind, options: options))

        let frame = FloatingHUDPositioner.frame(
            for: position,
            hudSize: FloatingHUDContentView.estimatedSize,
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
