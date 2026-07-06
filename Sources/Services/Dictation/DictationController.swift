import AppKit

/// Orchestrates a dictation session: hold the hotkey → record → transcribe →
/// paste into the frontmost app, driving the notch through its phases. The
/// transcriber is injected so ListenToMe's Whisper/Parakeet backends can be
/// swapped in behind `DictationTranscriber` later.
@MainActor
final class DictationController {
    private let model: NotchViewModel
    private let hotkey = DictationHotkey()
    private var transcriber: DictationTranscriber
    private var isRecording = false

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
        hotkey.start()
    }

    /// Manual toggle (menu item) — starts if idle, stops if recording.
    func toggle() {
        if isRecording { endRecording() } else { beginRecording() }
    }

    private func beginRecording() {
        guard !isRecording else { return }
        isRecording = true
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
            let text = await transcriber.finish()
            if text.isEmpty {
                model.setDictation(.error("Couldn't hear that"))
            } else {
                Paster.paste(text)
                model.setDictation(.success(text))
            }
        }
    }
}
