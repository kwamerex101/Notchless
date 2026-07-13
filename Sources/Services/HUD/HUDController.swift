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
    private lazy var presenter = HUDPresenter(model: model)
    private var settingsObservers: Set<AnyCancellable> = []

    /// Timestamp of the last `.soundUp`/`.soundDown`/`.mute` media-key press,
    /// used to correlate an `.external` volume change with a physical key
    /// press within `shouldShowVolumeHUD`'s `keyWindow`.
    private var lastVolumeKeyAt: Date?

    init(model: NotchViewModel) {
        self.model = model
    }

    func start() {
        presenter.applyValue = { [weak self] kind, value in self?.applyHUDValue(kind, value) }
        audio.onChange = { [weak self] level, muted, origin in
            guard let self, self.model.settings.soundHUDEnabled else { return }
            let shouldShow = Self.shouldShowVolumeHUD(
                origin: origin,
                showOnExternal: self.model.settings.showOnExternalVolumeEvent,
                axTrusted: AXIsProcessTrusted(),
                lastVolumeKeyAt: self.lastVolumeKeyAt,
                now: Date()
            )
            guard shouldShow else { return }
            self.presenter.show(.sound(level: level, muted: muted))
            // MediaMate parity: beep on a real key/external volume change,
            // never on `.selfWrite` (HUD drag would machine-gun) or
            // `.initial` (launch snapshot never shows anyway, since
            // `shouldShow` is already false for it).
            if self.model.settings.hudSoundOnChange, origin != .selfWrite, origin != .initial {
                HUDSoundPlayer.shared.play(self.model.settings.hudSoundName)
            }
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
                // The HUD itself is shown by AudioService's onChange; this
                // just timestamps the key press so shouldShowVolumeHUD can
                // correlate a subsequent .external CoreAudio change with it.
                self.lastVolumeKeyAt = Date()
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

    /// Pure decision for whether an audio-level change should surface the
    /// Sound HUD. `.initial` (the launch snapshot) never shows; `.selfWrite`
    /// (app-initiated, e.g. a HUD drag) always shows; `.external` shows when
    /// the user opted in to "Show on External Volume Event", or when
    /// Accessibility isn't trusted (we can't detect media keys, so we can't
    /// tell a legitimate key press from another app — default to showing),
    /// or when the change lands within `keyWindow` of a real media-key press.
    nonisolated static func shouldShowVolumeHUD(origin: VolumeChangeOrigin,
                                     showOnExternal: Bool,
                                     axTrusted: Bool,
                                     lastVolumeKeyAt: Date?,
                                     now: Date,
                                     keyWindow: TimeInterval = 0.3) -> Bool {
        switch origin {
        case .initial:
            return false
        case .selfWrite:
            return true
        case .external:
            if showOnExternal { return true }
            if !axTrusted { return true }
            guard let lastVolumeKeyAt else { return false }
            return now.timeIntervalSince(lastVolumeKeyAt) <= keyWindow
        }
    }

    /// Drives the live system setter for a click-drag on the floating HUD
    /// (Phase 5). Wired into `presenter.applyValue` in `start()`. Volume goes
    /// through `AudioService.setVolume`, which stamps the write `.selfWrite`
    /// so the resulting CoreAudio callback doesn't loop back into showing
    /// another HUD. Brightness prefers the built-in setter when available,
    /// falling back to `ExternalBrightnessBridge` only when the user opted
    /// into delegating external-display brightness.
    private func applyHUDValue(_ kind: HUDKind, _ value: Double) {
        switch kind {
        case .sound:
            audio.setVolume(value)
        case .display:
            if DisplayService.shared.setterAvailable && DisplayService.shared.isBuiltIn() {
                DisplayService.shared.setBrightness(value)
            } else if model.settings.externalBrightnessDelegate {
                ExternalBrightnessBridge.shared.setExternalBrightness(value)
            }
        }
    }

    private func showBrightnessHUD() {
        // Brightness settles a frame after the key event; read shortly after.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            let level = DisplayService.shared.brightness() ?? 0
            self.presenter.show(.display(level: level))
        }
    }
}
