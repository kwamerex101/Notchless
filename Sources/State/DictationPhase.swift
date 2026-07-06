import Foundation

/// The phases a dictation session moves through, shown in the notch. Mirrors
/// ListenToMe's pill states, re-surfaced as notch content.
enum DictationPhase: Equatable {
    case recording          // capturing audio — live waveform
    case transcribing       // audio captured, running speech-to-text
    case cleaning           // optional on-device transcript cleanup
    case success(String)    // final text (also pasted to the active app)
    case error(String)

    var isActive: Bool {
        switch self {
        case .recording, .transcribing, .cleaning: return true
        case .success, .error: return false
        }
    }

    var label: String {
        switch self {
        case .recording: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .cleaning: return "Polishing…"
        case .success: return "Done"
        case .error: return "Couldn't hear that"
        }
    }

    var systemImage: String {
        switch self {
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .cleaning: return "sparkles"
        case .success: return "checkmark"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}
