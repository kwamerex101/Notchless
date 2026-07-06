import AppKit

/// Soft system sounds when recording starts and when text lands.
enum SoundCue {
    static func recordingStarted() { NSSound(named: "Tink")?.play() }
    static func delivered() { NSSound(named: "Pop")?.play() }
    static func failed() { NSSound(named: "Funk")?.play() }
}
