import AppKit

/// Orchestrates a dictation session: hold the hotkey → record → transcribe →
/// polish → deliver, driving the notch through its phases. Reads all behaviour
/// from `model.dictationSettings`. The transcriber is injected so ListenToMe's
/// Whisper/Parakeet backends can be swapped in behind `DictationTranscriber`.
@MainActor
final class DictationController {
    private let model: NotchViewModel
    private let hotkey = DictationHotkey()
    /// A test/override backend; when nil the engine is chosen per-recording
    /// from `settings.engine`.
    private let injectedTranscriber: DictationTranscriber?
    private var transcriber: DictationTranscriber
    private var isRecording = false
    private var maxDurationTimer: Timer?
    /// The app that was frontmost when recording began — the delivery target,
    /// captured up front because it won't change (the notch panel never
    /// activates), and used to tailor cleanup tone.
    private var capturedContext: AppContext?
    private let escTap = EscapeKeyTap()
    private var session = SessionGuard()
    private var activeMode: Mode = Mode(id: Mode.defaultID, name: "Default", systemImage: "mic")
    private var effective: EffectiveDictation = DictationSettings.shared.effectiveBase

    private var settings: DictationSettings { model.dictationSettings }

    init(model: NotchViewModel, transcriber: DictationTranscriber? = nil) {
        self.model = model
        self.injectedTranscriber = transcriber
        self.transcriber = transcriber ?? SpeechTranscriber()
    }

    func start() {
        hotkey.onPress = { [weak self] in self?.beginRecording() }
        hotkey.onRelease = { [weak self] in self?.endRecording() }
        hotkey.requiredFlags = settings.hotkey.requiredFlags
        hotkey.start()
        model.dictationController = self
        escTap.onEscape = { [weak self] in self?.cancelRecording() }
    }

    /// Manual toggle (menu item) — starts if idle, stops if recording.
    func toggle() {
        if isRecording { endRecording() } else { beginRecording() }
    }

    private func beginRecording() {
        guard settings.enabled, !isRecording else {
            DictationLog.log("beginRecording ignored (enabled=\(settings.enabled), isRecording=\(isRecording))")
            return
        }
        isRecording = true
        capturedContext = AppContext.current()
        let mode = ModeStore.shared.resolve(forBundleID: capturedContext?.bundleID)
        activeMode = mode
        effective = mode.applied(over: settings.effectiveBase)
        model.dictationModeName = (mode.id == Mode.defaultID) ? nil : mode.name
        DictationLog.log("beginRecording engine=\(effective.engine.rawValue) mode=\(activeMode.name)")
        let frontApp = NSWorkspace.shared.frontmostApplication
        model.dictationTarget = DictationTarget(name: frontApp?.localizedName ?? "", icon: frontApp?.icon)
        model.audio.resetDictation()
        let generation = session.begin()

        // Pick up any hotkey change since launch.
        hotkey.requiredFlags = settings.hotkey.requiredFlags
        transcriber = makeTranscriber()
        transcriber.onLevel = { [weak self] level in
            guard let self, self.session.isCurrent(generation) else { return }
            self.model.audio.dictationLevel = level
        }
        transcriber.onSpectrum = { [weak self] spectrum in
            guard let self, self.session.isCurrent(generation) else { return }
            self.model.audio.dictationSpectrum = spectrum
        }
        transcriber.onPartial = { [weak self] partial in
            guard let self, self.session.isCurrent(generation) else { return }
            self.model.audio.dictationPartial = partial
        }
        model.setDictation(.recording)
        escTap.start()
        if settings.soundCues { SoundCue.recordingStarted() }
        startMaxDurationTimer()
        Task {
            do {
                try await transcriber.start()
                DictationLog.log("capture started")
            } catch {
                guard session.isCurrent(generation) else { return }
                isRecording = false
                escTap.stop()
                let message = (error as? DictationError)?.errorDescription
                    ?? (error as? ParakeetError)?.errorDescription ?? "Couldn't start"
                DictationLog.log("capture start FAILED: \(message) (\(error))")
                model.setDictation(.error(message))
            }
        }
    }

    /// Builds and configures the backend for the currently selected engine.
    /// An injected transcriber (tests) always wins.
    private func makeTranscriber() -> DictationTranscriber {
        if let injectedTranscriber { return injectedTranscriber }
        switch effective.engine {
        case .appleSpeech:
            let speech = SpeechTranscriber()
            speech.configure(languageID: effective.languageID, microphoneUID: settings.microphoneUID)
            return speech
        case .parakeet:
            let parakeet = ParakeetTranscriber()
            parakeet.configure(microphoneUID: settings.microphoneUID)
            return parakeet
        }
    }

    /// Combines the frontmost-app category hint with any learned per-app tone,
    /// used to tailor the cleanup prompt. Empty when context-aware cleanup is off.
    private func contextHint() -> String? {
        guard settings.contextAwareCleanup, let context = capturedContext else { return nil }
        let parts = [context.category.promptHint, StyleStore.shared.promptHint(for: context.bundleID)]
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// The mode's custom instruction (if any) followed by the learned context hint.
    private func combinedHint() -> String? {
        let parts = [effective.instruction, contextHint()].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func startMaxDurationTimer() {
        maxDurationTimer?.invalidate()
        let seconds = max(5, settings.maxRecordingSeconds)
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.endRecording() }
        }
    }

    /// Abort the current recording without transcribing/pasting.
    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        maxDurationTimer?.invalidate()
        escTap.stop()
        _ = session.begin() // invalidate any in-flight writes from this session
        transcriber.cancel()
        model.audio.resetDictation()
        model.setDictation(nil)
        if settings.soundCues { SoundCue.failed() }
        DictationLog.log("cancelRecording")
    }

    private func endRecording() {
        guard isRecording else { return }
        isRecording = false
        maxDurationTimer?.invalidate()
        escTap.stop()
        let generation = session.begin()
        DictationLog.log("endRecording → transcribing")
        model.setDictation(.transcribing)
        Task {
            let raw = await transcriber.finish()
            guard session.isCurrent(generation) else { return }
            DictationLog.log("transcript raw=\"\(raw.prefix(120))\" (len=\(raw.count))")
            guard !raw.isEmpty else {
                if settings.soundCues { SoundCue.failed() }
                model.setDictation(.error("Couldn't hear that"))
                return
            }
            var text = TranscriptHygiene.clean(raw)
            if effective.voiceCommands { text = SpokenCommands.apply(text) }
            if effective.smartFormatting { text = BuiltinTransforms.apply(text) }
            text = DictationSnippets.shared.expand(text)
            text = TextPolish.apply(
                text,
                dictionary: model.dictationDictionary.terms,
                capitalize: effective.autoCapitalize
            )
            // Optional AI polish; falls back to `text` on any failure/timeout.
            if TranscriptCleaner.shouldClean(text, mode: effective.cleanup) {
                model.setDictation(.cleaning)
                text = await TranscriptCleaner.clean(
                    text,
                    backend: settings.cleanupBackend,
                    intensity: effective.cleanupIntensity,
                    timeoutSeconds: settings.cleanupTimeoutSeconds,
                    apiKey: settings.anthropicAPIKey,
                    extraPromptHint: combinedHint()
                )
                guard session.isCurrent(generation) else { return }
            }
            model.dictationHistory.add(text, retentionDays: settings.historyRetentionDays)
            DictationOutputRouter.deliver(text, to: effective.output)
            if let bundleID = capturedContext?.bundleID {
                StyleStore.shared.observe(text: text, bundleID: bundleID)
            }
            DictationLog.log("delivered via \(effective.output.rawValue): \"\(text.prefix(120))\"")
            if settings.soundCues { SoundCue.delivered() }
            model.setDictation(.success(text))
        }
    }
}
