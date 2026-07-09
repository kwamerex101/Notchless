import SwiftUI

/// High-frequency audio levels, kept in a dedicated observable so the ~30 Hz
/// visualizer stream only invalidates the visualizer subtree — not the whole
/// `NotchViewModel` and, through it, the entire notch view tree. Owned by
/// `NotchViewModel` but deliberately NOT republished through it.
@MainActor
final class AudioLevelsModel: ObservableObject {
    /// Live audio-band levels (low→high) from the system-audio tap, driving the
    /// now-playing visualizer. Empty when not capturing.
    @Published var musicSpectrum: [CGFloat] = []

    /// Live dictation input level 0…1 for the recording waveform.
    @Published var dictationLevel: CGFloat = 0.5
    /// Live dictation frequency-band levels (low→high).
    @Published var dictationSpectrum: [CGFloat] = []

    /// Live partial transcript from the recognizer (Apple Speech only; Parakeet
    /// finishes-then-transcribes and never emits partials). High-frequency, so
    /// it lives here and not on `NotchViewModel`.
    @Published var dictationPartial: String = ""

    /// Clear dictation state at the start/cancel of a session. `dictationLevel`
    /// defaults to 0.5, which would flash a phantom half-height bar before real
    /// audio arrives — reset it to the silence floor.
    func resetDictation() {
        dictationLevel = 0
        dictationSpectrum = []
        dictationPartial = ""
    }
}
