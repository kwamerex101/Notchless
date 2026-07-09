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
}
