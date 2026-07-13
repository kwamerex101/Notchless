import AppKit
import Combine

/// Coordinates the Sound / Display HUDs: CoreAudio drives Sound, the media-key
/// tap drives Display (reading brightness after the key adjusts it). Respects
/// the per-HUD settings toggles. See PLAN.md §1.1, Phase 3.
///
/// System OSD suppression is no longer per-event: `OSDSuppressor` is stateful
/// (SIGSTOPs `OSDUIHelper` once and keeps it stopped while the
/// `suppressSystemOSD` setting is on), so this controller only activates or
/// deactivates it on `start()` and whenever the setting changes.
@MainActor
final class HUDController {
    private let model: NotchViewModel
    private let audio = AudioService()
    private let keys = MediaKeyTap()
    private var settingsObservers: Set<AnyCancellable> = []

    init(model: NotchViewModel) {
        self.model = model
    }

    func start() {
        audio.onChange = { [weak self] level, muted, origin in
            guard let self, self.model.settings.soundHUDEnabled else { return }
            // Skip the initial snapshot so we don't flash a HUD on launch.
            // AudioService itself tags this .initial; any other origin
            // (.selfWrite or .external) shows the HUD for now.
            guard origin != .initial else { return }
            self.model.showHUD(.sound(level: level, muted: muted))
        }
        audio.onDeviceChange = { [weak self] supportsVolume in
            guard let self else { return }
            if !supportsVolume, OSDSuppressor.shared.isActive {
                OSDSuppressor.shared.deactivate()
            } else if supportsVolume {
                self.applySuppressionSetting()
            }
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

        applySuppressionSetting()
        // `@Stored` has no per-key publisher, so — as elsewhere in this
        // codebase — coarse-observe `objectWillChange` and reread the
        // current value, debounced so a settings-window drag doesn't
        // thrash activate()/deactivate().
        model.settings.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.applySuppressionSetting() }
            .store(in: &settingsObservers)
    }

    private func applySuppressionSetting() {
        if model.settings.suppressSystemOSD {
            OSDSuppressor.shared.activate()
        } else {
            OSDSuppressor.shared.deactivate()
        }
    }

    private func showBrightnessHUD() {
        // Brightness settles a frame after the key event; read shortly after.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            let level = DisplayService.shared.brightness() ?? 0
            self.model.showHUD(.display(level: level))
        }
    }
}
