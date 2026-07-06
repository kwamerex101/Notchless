import AppKit

/// Coordinates the Sound / Display HUDs: CoreAudio drives Sound, the media-key
/// tap drives Display (reading brightness after the key adjusts it). Respects
/// the per-HUD settings toggles. See PLAN.md §1.1, Phase 3.
@MainActor
final class HUDController {
    private let model: NotchViewModel
    private let audio = AudioService()
    private let keys = MediaKeyTap()
    private var primed = false

    init(model: NotchViewModel) {
        self.model = model
    }

    func start() {
        audio.onChange = { [weak self] level, muted in
            guard let self, self.model.settings.soundHUDEnabled else { return }
            // Skip the initial snapshot so we don't flash a HUD on launch.
            guard self.primed else { self.primed = true; return }
            OSDSuppressor.suppress()
            self.model.showHUD(.sound(level: level, muted: muted))
            self.scheduleRestore()
        }
        audio.start()

        keys.onKey = { [weak self] key in
            guard let self else { return }
            switch key {
            case .brightnessUp, .brightnessDown:
                guard self.model.settings.displayHUDEnabled else { return }
                self.showBrightnessHUD()
            case .soundUp, .soundDown, .mute:
                break // handled by AudioService
            }
        }
        keys.start()
    }

    private func showBrightnessHUD() {
        // Brightness settles a frame after the key event; read shortly after.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            let level = DisplayService.shared.brightness() ?? 0
            OSDSuppressor.suppress()
            self.model.showHUD(.display(level: level))
            self.scheduleRestore()
        }
    }

    private func scheduleRestore() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            OSDSuppressor.restore()
        }
    }
}
