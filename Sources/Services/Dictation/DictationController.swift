import AppKit

/// Orchestrates a dictation session: hold the hotkey → record → transcribe →
/// polish → deliver, driving the notch through its phases. Reads all behaviour
/// from `model.dictationSettings`. The transcriber is injected so ListenToMe's
/// Whisper/Parakeet backends can be swapped in behind `DictationTranscriber`.
@MainActor
final class DictationController {
    private let model: NotchViewModel
    private let hotkey = DictationHotkey()
    private var transcriber: DictationTranscriber
    private var isRecording = false

    private var settings: DictationSettings { model.dictationSettings }

    init(model: NotchViewModel, transcriber: DictationTranscriber? = nil) {
        self.model = model
        self.transcriber = transcriber ?? SpeechTranscriber()
    }

    func start() {
        transcriber.onLevel = { [weak self] level in
            self?.model.dictationLevel = level
        }
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
        if let speech = transcriber as? SpeechTranscriber {
            speech.configure(languageID: settings.languageID, microphoneUID: settings.microphoneUID)
        }
        model.setDictation(.recording)
        Task {
            do {
                try await transcriber.start()
            } catch {
                isRecording = false
                model.setDictation(.error((error as? DictationError)?.errorDescription ?? "Couldn't start"))
            }
        }
    }

    private func endRecording() {
        guard isRecording else { return }
        isRecording = false
        model.setDictation(.transcribing)
        Task {
            let raw = await transcriber.finish()
            guard !raw.isEmpty else {
                model.setDictation(.error("Couldn't hear that"))
                return
            }
            let polished = TextPolish.apply(
                raw,
                dictionary: model.dictationDictionary.terms,
                capitalize: settings.autoCapitalize
            )
            model.dictationHistory.add(polished, retentionDays: settings.historyRetentionDays)
            DictationOutputRouter.deliver(polished, to: settings.output)
            model.setDictation(.success(polished))
        }
    }
}
