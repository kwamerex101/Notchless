import Foundation

/// A speech-to-text backend for dictation. Phase 1 ships an on-device Apple
/// Speech implementation; ListenToMe's Whisper/Parakeet engines can be added as
/// alternative conformers behind this same protocol (see the integration notes
/// in STATUS.md).
@MainActor
protocol DictationTranscriber: AnyObject {
    /// Partial (interim) transcript updates while the user speaks.
    var onPartial: ((String) -> Void)? { get set }
    /// Normalized input level 0…1 for the live waveform.
    var onLevel: ((CGFloat) -> Void)? { get set }

    /// Requests permissions and begins capturing + transcribing.
    func start() async throws
    /// Stops capture and returns the final transcript (may be empty).
    func finish() async -> String
    /// Aborts without producing output.
    func cancel()
}

enum DictationError: LocalizedError {
    case microphoneDenied
    case speechDenied
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: return "Microphone access is off"
        case .speechDenied: return "Speech recognition access is off"
        case .recognizerUnavailable: return "Speech recognition unavailable"
        }
    }
}
