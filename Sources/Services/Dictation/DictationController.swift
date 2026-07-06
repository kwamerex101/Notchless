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
    }

    /// Manual toggle (menu item) — starts if idle, stops if recording.
    func toggle() {
        if isRecording { endRecording() } else { beginRecording() }
    }

    private func beginRecording() {
        guard settings.enabled, !isRecording else { return }
        isRecording = true
        // Pick up any hotkey change since launch.
        hotkey.requiredFlags = settings.hotkey.requiredFlags
        transcriber = makeTranscriber()
        transcriber.onLevel = { [weak self] level in
            self?.model.dictationLevel = level
        }
        model.setDictation(.recording)
        if settings.soundCues { SoundCue.recordingStarted() }
        startMaxDurationTimer()
        Task {
            do {
                try await transcriber.start()
            } catch {
                isRecording = false
                model.setDictation(.error((error as? DictationError)?.errorDescription ?? "Couldn't start"))
            }
        }
    }

    /// Builds and configures the backend for the currently selected engine.
    /// An injected transcriber (tests) always wins.
    private func makeTranscriber() -> DictationTranscriber {
        if let injectedTranscriber { return injectedTranscriber }
        switch settings.engine {
        case .appleSpeech:
            let speech = SpeechTranscriber()
            speech.configure(languageID: settings.languageID, microphoneUID: settings.microphoneUID)
            return speech
        case .parakeet:
            let parakeet = ParakeetTranscriber()
            parakeet.configure(microphoneUID: settings.microphoneUID)
            return parakeet
        }
    }

    private func startMaxDurationTimer() {
        maxDurationTimer?.invalidate()
        let seconds = max(5, settings.maxRecordingSeconds)
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.endRecording() }
        }
    }

    private func endRecording() {
        guard isRecording else { return }
        isRecording = false
        maxDurationTimer?.invalidate()
        model.setDictation(.transcribing)
        Task {
            let raw = await transcriber.finish()
            guard !raw.isEmpty else {
                if settings.soundCues { SoundCue.failed() }
                model.setDictation(.error("Couldn't hear that"))
                return
            }
            var text = raw
            if settings.voiceCommands { text = SpokenCommands.apply(text) }
            text = DictationSnippets.shared.expand(text)
            text = TextPolish.apply(
                text,
                dictionary: model.dictationDictionary.terms,
                capitalize: settings.autoCapitalize
            )
            // Optional AI polish (Claude CLI); falls back to `text` if unavailable.
            if TranscriptCleaner.shouldClean(text, mode: settings.cleanup) {
                model.setDictation(.cleaning)
                text = await TranscriptCleaner.clean(text)
            }
            model.dictationHistory.add(text, retentionDays: settings.historyRetentionDays)
            DictationOutputRouter.deliver(text, to: settings.output)
            if settings.soundCues { SoundCue.delivered() }
            model.setDictation(.success(text))
        }
    }
}
