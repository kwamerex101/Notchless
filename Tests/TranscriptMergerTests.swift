import XCTest
@testable import Notchless

final class TranscriptMergerTests: XCTestCase {
    func testMergesByStartTimeAndCoalescesConsecutiveSameSpeaker() {
        let you = [
            TranscriptSegment(speaker: .you, start: 0.0, end: 1.0, text: "Hi", qualityScore: nil),
            TranscriptSegment(speaker: .you, start: 4.0, end: 5.0, text: "Sounds good", qualityScore: nil),
        ]
        let remote = [
            TranscriptSegment(speaker: .remote(id: "SPEAKER_00", name: nil), start: 1.2, end: 3.5,
                              text: "Hello there", qualityScore: 0.8),
        ]
        let merged = TranscriptMerger.merge(you: you, remote: remote, duration: 5.0)
        XCTAssertEqual(merged.segments.map(\.text), ["Hi", "Hello there", "Sounds good"])
        XCTAssertEqual(merged.segments.map(\.speaker),
                       [.you, .remote(id: "SPEAKER_00", name: nil), .you])
        XCTAssertEqual(merged.duration, 5.0)
    }

    func testDropsEmptyTextSegments() {
        let you = [TranscriptSegment(speaker: .you, start: 0, end: 1, text: "   ", qualityScore: nil)]
        let merged = TranscriptMerger.merge(you: you, remote: [], duration: 1)
        XCTAssertTrue(merged.segments.isEmpty)
    }
}
