import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = NotchViewModel()

    private var panel: NotchPanel?
    private var mouseTracker: NotchMouseTracker?
    private let panelSize = NSSize(width: 760, height: 460)
    /// The screen the panel currently sits on (compared by frame), and a timer
    /// that keeps the panel on whichever screen the user is using.
    private var currentScreenFrame: NSRect?
    private var followTimer: Timer?
    private var settingsObservers: Set<AnyCancellable> = []

    private lazy var media = MediaController(model: model)
    private lazy var hud = HUDController(model: model)
    private lazy var battery = BatteryController(model: model)
    private lazy var stats = StatsController(model: model)
    private lazy var timerController = TimerController(model: model)
    private lazy var privacy = PrivacyController(model: model)
    private lazy var claudeStats = ClaudeStatsController(model: model)
    private lazy var audioTap = SystemAudioTap(model: model)
    private var playbackObserver: AnyCancellable?
    private lazy var calendar = CalendarController(model: model)
    private lazy var notifications = NotificationsController(model: model)
    private(set) lazy var dictation = DictationController(model: model)
    private(set) lazy var meeting = MeetingController(
        capture: MeetingCaptureService(systemTap: audioTap),
        pipeline: MeetingTranscriptionPipeline(),
        summarizer: MeetingSummarizer(
            client: AnthropicMinutesAPIClient(keyProvider: { DictationSettings.shared.anthropicAPIKey }),
            model: UserDefaults.standard.string(forKey: "meeting.summarizerModel") ?? "claude-sonnet-5"),
        store: MeetingStore(directory: MeetingStore.defaultDirectory()),
        makeSummarizer: {
            // Backend + model read live so Settings changes take effect without relaunch.
            let model = UserDefaults.standard.string(forKey: "meeting.summarizerModel") ?? "claude-sonnet-5"
            let client: MinutesAPIClient
            switch MeetingSummaryBackend.current {
            case .subscription:
                client = ClaudeCLIMinutesClient()
            case .apiKey:
                client = AnthropicMinutesAPIClient(keyProvider: { DictationSettings.shared.anthropicAPIKey })
            }
            return MeetingSummarizer(client: client, model: model)
        })
    private var effects: EffectsController?
    private lazy var trackpadFeedback = TrackpadFeedbackController(settings: model.settings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        GoalSelfTest.run()   // no-op unless DI_GOAL_SELFTEST is set
        #endif
        NSApp.setActivationPolicy(.accessory)
        buildPanel()

        // Permission-free services start immediately.
        media.start()
        battery.start()
        stats.start()
        timerController.start()
        privacy.start()
        claudeStats.start()
        ClipboardStore.shared.start()

        // Dormant unless the user enables it in Settings (default off) — the
        // Accessibility prompt only fires when they flip the toggle.
        trackpadFeedback.start()

        // Expose the meeting-capture controller so the notch record control can
        // reach it. Constructing it is side-effect-free; capture starts only when
        // the user taps Record.
        model.meeting = meeting

        // Keep the feature-gated pollers in sync with their toggles at runtime,
        // so turning a feature off actually stops its timer (and turning it back
        // on resumes live — no relaunch).
        model.settings.$statsEnabled.removeDuplicates()
            .sink { [weak self] on in self?.stats.setEnabled(on) }
            .store(in: &settingsObservers)
        model.settings.$privacyIndicatorEnabled.removeDuplicates()
            .sink { [weak self] on in self?.privacy.setEnabled(on) }
            .store(in: &settingsObservers)
        model.settings.$clipboardEnabled.removeDuplicates()
            .sink { on in ClipboardStore.shared.setEnabled(on) }
            .store(in: &settingsObservers)

        // Capture system audio only while music is playing AND its visualizer is
        // actually on screen — swiping to another page stops the tap, swiping
        // back restarts it. `objectWillChange` (debounced so it reads the
        // settled state) covers content changes; the settings toggle covers the
        // preference. start()/stop() are idempotent.
        playbackObserver = model.objectWillChange
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.updateAudioTap() }
        model.settings.$liveAudioVisualizer.removeDuplicates()
            .sink { [weak self] _ in self?.updateAudioTap() }
            .store(in: &settingsObservers)
        updateAudioTap()
        effects = EffectsController(settings: model.settings, panel: panel)
        effects?.start()

        // Services that trigger system permission prompts wait until the user
        // has been primed by onboarding (or it's already been completed).
        OnboardingWindowController.shared.presentIfNeeded { [weak self] in
            self?.startPermissionedServices()
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )

        // Follow the screen the user is using — but only in Active-display mode,
        // where the target screen depends on the live cursor position. The other
        // modes reposition via didChangeScreenParametersNotification, so their
        // 0.35s timer would just burn wakeups. Track the mode live.
        model.settings.$simulatedDisplay.removeDuplicates()
            .sink { [weak self] mode in self?.updateFollowTimer(for: mode) }
            .store(in: &settingsObservers)
    }

    private func updateFollowTimer(for mode: SimulatedDisplay) {
        followTimer?.invalidate()
        followTimer = nil
        guard mode == .active else { return }
        repositionIfNeeded()   // snap to the current screen on entering Active mode
        followTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.repositionIfNeeded() }
        }
    }

    /// Starts the system-audio tap when music is playing, its visualizer is on
    /// screen, and the setting is on; stops it otherwise. Idempotent.
    private func updateAudioTap() {
        let visualizerWants = model.nowPlaying?.isPlaying == true
            && model.settings.liveAudioVisualizer
            && model.visualizerOnScreen
        // A meeting also needs the tap running to capture the far side, even with no music.
        // meeting.phase changes propagate to model.objectWillChange (NotchViewModel bridges it),
        // so this re-evaluates when a capture starts/stops.
        let wanted = visualizerWants || (model.meeting?.isCapturing == true)
        if wanted { audioTap.start() } else { audioTap.stop() }
    }

    private func startPermissionedServices() {
        hud.start()
        calendar.start()
        notifications.start()
        dictation.start()
    }

    private func makeRootView(_ metrics: NotchMetrics) -> NotchRootView {
        NotchRootView(
            model: model,
            metrics: metrics,
            onCommand: { [weak self] cmd in self?.media.send(cmd) },
            onOpenSettings: { [weak self] in
                guard let self else { return }
                SettingsWindowController.shared.show(meeting: self.meeting)
            }
        )
    }

    private func buildPanel() {
        guard let screen = targetScreen() else { return }
        let metrics = NotchGeometry.metrics(for: screen)
        let frame = panelFrame(for: metrics)

        #if DEBUG
        DebugRender.run(metrics: metrics)  // no-op unless DI_DEBUG_RENDER is set
        #endif
        let panel = NotchPanel(contentRect: frame)
        let host = NotchHostingView(rootView: makeRootView(metrics), model: model, metrics: metrics)
        host.onMediaCommand = { [weak self] in self?.media.send($0) }
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        self.panel = panel
        self.currentScreenFrame = screen.frame

        // Let in-notch text fields borrow keyboard focus while editing. The app
        // is an accessory (no Dock icon); activating it briefly is the reliable
        // way for a non-activating panel to receive typing, and we hand focus
        // back when editing ends.
        model.requestKeyFocus = { [weak panel] want in
            guard let panel else { return }
            panel.wantsKey = want
            if want {
                NSApp.activate(ignoringOtherApps: true)
                panel.makeKeyAndOrderFront(nil)
            } else {
                NSApp.deactivate()
            }
        }

        let tracker = NotchMouseTracker(panel: panel, model: model, metrics: metrics)
        tracker.start()
        self.mouseTracker = tracker
    }

    /// Moves the panel to `screen` and refreshes its notch geometry.
    private func applyScreen(_ screen: NSScreen) {
        guard let panel else { return }
        let metrics = NotchGeometry.metrics(for: screen)
        panel.setFrame(panelFrame(for: metrics), display: true)
        if let host = panel.contentView as? NotchHostingView {
            host.metrics = metrics
            host.rootView = makeRootView(metrics)
        }
        mouseTracker?.metrics = metrics
        currentScreenFrame = screen.frame
    }

    /// Repositions only when the target screen changed — driven by the follow
    /// timer, so Active-display mode tracks the screen you're on.
    private func repositionIfNeeded() {
        guard let screen = targetScreen(), screen.frame != currentScreenFrame else { return }
        applyScreen(screen)
    }

    private func targetScreen() -> NSScreen? {
        switch model.settings.simulatedDisplay {
        case .builtIn:
            return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        case .active:
            return NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        case .main:
            return NSScreen.main
        }
    }

    private func panelFrame(for metrics: NotchMetrics) -> NSRect {
        NSRect(
            x: metrics.notchCenterX - panelSize.width / 2,
            y: metrics.screenTopY - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        followTimer?.invalidate()
        media.stop()
    }

    @objc private func screensChanged() {
        // A display was added/removed/rearranged — re-apply even if it's the
        // same screen, since its frame or notch geometry may have changed.
        guard let screen = targetScreen() else { return }
        applyScreen(screen)
    }
}
