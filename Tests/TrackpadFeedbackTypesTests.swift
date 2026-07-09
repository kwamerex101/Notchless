import XCTest
@testable import Notchless

final class TrackpadFeedbackTypesTests: XCTestCase {
    func test_hapticStrength_threeCases() {
        XCTAssertEqual(HapticStrength.allCases, [.light, .medium, .strong])
    }

    func test_voiceCatalog_hasUniqueIDsAndNames() {
        let voices = FeedbackVoice.all
        XCTAssertGreaterThanOrEqual(voices.count, 3)
        XCTAssertEqual(Set(voices.map(\.id)).count, voices.count)
        XCTAssertEqual(Set(voices.map(\.assetName)).count, voices.count)
    }

    func test_voiceLookup_fallsBackToFirst() {
        XCTAssertEqual(FeedbackVoice.voice(id: "nope"), FeedbackVoice.all[0])
        XCTAssertEqual(FeedbackVoice.voice(id: "twig").id, "twig")
    }

    // MARK: - TrackpadHapticEngine (pure/CI-safe parts only)

    func test_strengthToActuationID_mapping() {
        XCTAssertEqual(TrackpadHapticEngine.actuationID(for: .light), 3)
        XCTAssertEqual(TrackpadHapticEngine.actuationID(for: .medium), 4)
        XCTAssertEqual(TrackpadHapticEngine.actuationID(for: .strong), 6)
    }

    func test_engine_neverCrashes_evenIfUnavailable() {
        // On CI (no Force Touch trackpad / VM) this exercises the no-op path;
        // on a MacBook it exercises the real one. Either way: no crash.
        let engine = TrackpadHapticEngine()
        engine.actuate(.medium)
        engine.close()
        _ = TrackpadHapticEngine.probeAvailability()
    }
}
