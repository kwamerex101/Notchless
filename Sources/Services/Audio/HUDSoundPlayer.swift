import AppKit

/// MediaMate parity: "Play [Beep] when the volume is changed" — a short
/// system sound on real (non-`.selfWrite`, non-`.initial`) volume changes.
/// See `HUDController.audio.onChange` for the origin gate.
enum HUDSound: String, CaseIterable, Codable, StoredValue {
    case pop, tink, funk, submarine

    var displayName: String { rawValue.capitalized }

    /// The macOS system sound name for `NSSound(named:)`. PURE — unit-tested
    /// in `HUDSoundTests`; actual playback is on-device only.
    var systemSoundName: String {
        switch self {
        case .pop: "Pop"
        case .tink: "Tink"
        case .funk: "Funk"
        case .submarine: "Submarine"
        }
    }
}

/// Plays `HUDSound`s via `NSSound`. Best-effort — a missing/unloadable
/// system sound is a silent no-op, never a crash.
@MainActor
final class HUDSoundPlayer {
    static let shared = HUDSoundPlayer()

    private init() {}

    func play(_ sound: HUDSound) {
        NSSound(named: NSSound.Name(sound.systemSoundName))?.play()
    }
}
