import Foundation

/// Discrete haptic intensity. The Taptic Engine has no continuous amplitude —
/// each case maps to a built-in MTActuator waveform ID (see TrackpadHapticEngine).
enum HapticStrength: String, CaseIterable, Codable {
    case light, medium, strong

    var title: String {
        switch self {
        case .light: return "Light"
        case .medium: return "Medium"
        case .strong: return "Strong"
        }
    }

    var systemImage: String {
        switch self {
        case .light: return "wave.3.right"
        case .medium: return "wave.3.forward"
        case .strong: return "waveform.path"
        }
    }
}

/// A bundled click-sound voice. All samples are original, self-generated
/// (scripts/generate_click_voices.py) — CC0, no third-party assets.
struct FeedbackVoice: Identifiable, Hashable {
    let id: String
    let displayName: String
    let assetName: String   // wav resource name in the app bundle

    static let all: [FeedbackVoice] = [
        FeedbackVoice(id: "pebble", displayName: "Pebble", assetName: "pebble"),
        FeedbackVoice(id: "twig", displayName: "Twig", assetName: "twig"),
        FeedbackVoice(id: "drop", displayName: "Drop", assetName: "drop"),
    ]

    static func voice(id: String) -> FeedbackVoice {
        all.first { $0.id == id } ?? all[0]
    }
}

/// Tuning constants for the velocity-aware detent spacing. Defaults chosen
/// blind; confirmed by the on-device feel pass (Task 10).
struct DetentTuning {
    /// px of scroll per tick at rest.
    var baseThreshold: Double = 24
    /// extra px of threshold per (px/s) of velocity — spacing widens as you scroll faster.
    var velocityScale: Double = 0.02
    /// px/s above which ticks are suppressed entirely (the "blur" on a fling).
    var flingCutoff: Double = 6000
    /// seconds of quiet after which the accumulator treats input as a new gesture.
    var gestureGap: TimeInterval = 0.25
}

/// Immutable snapshot of the user's feedback settings. Built on the main actor
/// by TrackpadFeedbackController, read by the event-tap thread — value type,
/// so no shared mutable state crosses threads.
struct TrackpadFeedbackConfig: Equatable {
    var hapticsOn: Bool
    var soundOn: Bool
    var scrollOn: Bool
    var clickOn: Bool
    var strength: HapticStrength
    var voiceID: String
    var volume: Double
}

/// Haptic output seam — real MTActuator in production, mock in tests.
protocol HapticActuating: AnyObject {
    var isAvailable: Bool { get }
    func actuate(_ strength: HapticStrength)
}

/// Sound output seam — real AVAudioEngine player in production, mock in tests.
protocol ClickSounding: AnyObject {
    func preload()
    func play(_ voice: FeedbackVoice, volume: Double)
}
