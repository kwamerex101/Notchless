import AppKit
import Combine
import ApplicationServices

/// Bridges SettingsStore to the trackpad-feedback machinery: builds immutable
/// config snapshots for the off-main core, owns start/stop lifecycle, and
/// handles the Accessibility permission dance. Dormant (zero cost) while the
/// master toggle is off — constructing it never prompts for permissions.
@MainActor
final class TrackpadFeedbackController: ObservableObject {
    static let testFeedbackNotification = Notification.Name("notchless.trackpadFeedback.test")

    /// True when the feature is enabled but Accessibility isn't granted —
    /// the Settings pane shows its Grant CTA off this.
    @Published private(set) var needsAccessibility = false

    private let settings: SettingsStore
    private let engine = TrackpadHapticEngine()
    private let player = ClickSoundPlayer()
    private var core: TrackpadFeedbackCore?
    private var monitor: TrackpadEventMonitor?
    private var gestureMonitor: MultitouchMonitor?
    private var observers: Set<AnyCancellable> = []
    private var trustPollTimer: Timer?
    /// Latches true once MultitouchMonitor.start() fails (no device present)
    /// so reconcileGestureMonitor() stops re-constructing a throwaway monitor
    /// (dlopen + wake-observer churn) on every settings-driven apply(). Reset
    /// on toggle-off and teardown so re-enabling retries.
    private var gestureStartFailed = false

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func start() {
        // Any settings change re-applies; apply() is cheap and idempotent.
        settings.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &observers)

        NotificationCenter.default.publisher(for: Self.testFeedbackNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.fireTest() }
            .store(in: &observers)

        apply()
    }

    /// Registers the app in the Accessibility list (system prompt) and opens
    /// System Settings — mirrors PermissionsModel.act(.accessibility).
    func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if let url = AppPermission.accessibility.settingsURL {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSWorkspace.shared.open(url) }
        }
    }

    // MARK: - Lifecycle

    private func apply() {
        guard settings.trackpadFeedbackEnabled else {
            teardown()
            needsAccessibility = false
            return
        }

        guard AXIsProcessTrusted() else {
            teardown()
            if !needsAccessibility {
                needsAccessibility = true
                promptForAccessibility()
            }
            startTrustPolling()
            return
        }

        needsAccessibility = false
        stopTrustPolling()
        ensureRunning()
        core?.update(config: currentConfig())
    }

    private func ensureRunning() {
        if core == nil {
            player.preload()
            core = TrackpadFeedbackCore(
                config: currentConfig(), tuning: DetentTuning(),
                actuator: engine, player: player)
        }
        if monitor == nil, let core {
            let monitor = TrackpadEventMonitor(core: core)
            if monitor.start() {
                self.monitor = monitor
            } else {
                // Tap creation failed (trust revoked between check and create) — re-poll.
                needsAccessibility = true
                startTrustPolling()
            }
        }
        reconcileGestureMonitor()
    }

    /// Start the gesture monitor when the sub-toggle is on; stop it when off, so
    /// the MT device isn't streaming frames we'd only discard. Called on every
    /// apply() while the feature is running.
    private func reconcileGestureMonitor() {
        guard let core else { return }
        if settings.trackpadGesturesEnabled {
            if gestureMonitor == nil, !gestureStartFailed {
                let m = MultitouchMonitor(core: core, tuning: GestureTuning())
                if m.start() {
                    gestureMonitor = m
                } else {
                    gestureStartFailed = true
                }
            }
        } else {
            gestureMonitor?.stop()
            gestureMonitor = nil
            gestureStartFailed = false
        }
    }

    private func teardown() {
        stopTrustPolling()
        monitor?.stop()
        monitor = nil
        gestureMonitor?.stop()
        gestureMonitor = nil
        gestureStartFailed = false
        core = nil
        engine.close()
    }

    private func currentConfig() -> TrackpadFeedbackConfig {
        TrackpadFeedbackConfig(
            hapticsOn: settings.trackpadHapticsEnabled,
            soundOn: settings.trackpadSoundEnabled,
            scrollOn: settings.trackpadFeedbackScroll,
            clickOn: settings.trackpadFeedbackClick,
            strength: settings.trackpadHapticStrength,
            voiceID: settings.trackpadSoundVoice,
            volume: settings.trackpadSoundVolume,
            gesturesOn: settings.trackpadGesturesEnabled)
    }

    private func fireTest() {
        // Works even before the feature is fully running (e.g. while trying
        // strengths before enabling): build a transient core if needed.
        if let core {
            core.fireTest()
        } else {
            player.preload()
            TrackpadFeedbackCore(
                config: currentConfig(), tuning: DetentTuning(),
                actuator: engine, player: player
            ).fireTest()
            // Feature isn't running, so nothing else will ever close this
            // transient actuator open — close it now rather than leaving the
            // MTActuator open for the rest of the app's lifetime.
            engine.close()
        }
    }

    // MARK: - Accessibility trust polling

    private func startTrustPolling() {
        guard trustPollTimer == nil else { return }
        trustPollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if AXIsProcessTrusted() { self.apply() }
            }
        }
    }

    private func stopTrustPolling() {
        trustPollTimer?.invalidate()
        trustPollTimer = nil
    }
}
