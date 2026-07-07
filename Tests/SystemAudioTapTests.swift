import XCTest
@testable import Notchless

/// Locks the silence-watchdog policy: a CoreAudio process tap can go dormant
/// (or start unauthorized) and deliver pure silence forever, so we recreate it
/// when music plays but no audio has flowed for a while. See `SystemAudioTap`.
final class SystemAudioTapTests: XCTestCase {
    private let grace = SystemAudioTap.silenceGrace
    private let cooldown = SystemAudioTap.recreateCooldown

    func test_recreates_whenPlayingAndSilentPastGrace() {
        XCTAssertTrue(SystemAudioTap.shouldRecreate(
            isPlaying: true, silentFor: grace + 0.1, sinceLastRecreate: cooldown + 0.1))
    }

    func test_doesNotRecreate_whenNotPlaying() {
        // Paused: the gate stops the tap; the watchdog must never fire.
        XCTAssertFalse(SystemAudioTap.shouldRecreate(
            isPlaying: false, silentFor: 999, sinceLastRecreate: 999))
    }

    func test_doesNotRecreate_duringBriefQuietPassage() {
        // A short silent stretch in a track is not dormancy.
        XCTAssertFalse(SystemAudioTap.shouldRecreate(
            isPlaying: true, silentFor: grace - 0.1, sinceLastRecreate: 999))
    }

    func test_doesNotRecreate_withinCooldown() {
        // A still-silent tap must not thrash: honor the cooldown between recreates.
        XCTAssertFalse(SystemAudioTap.shouldRecreate(
            isPlaying: true, silentFor: grace + 5, sinceLastRecreate: cooldown - 0.1))
    }
}
