import XCTest
@testable import Notchless

final class MeetingModelsTests: XCTestCase {
    func testSpeakerDisplayName() {
        XCTAssertEqual(Speaker.you.displayName([:]), "You")
        XCTAssertEqual(Speaker.remote(id: "SPEAKER_01", name: nil).displayName([:]), "Speaker 2")
        XCTAssertEqual(Speaker.remote(id: "SPEAKER_01", name: nil).displayName(["SPEAKER_01": "Sarah"]), "Sarah")
    }

    func testMeetingRecordRoundTrips() throws {
        let seg = TranscriptSegment(speaker: .you, start: 0, end: 1.5, text: "Hi", qualityScore: nil)
        let record = MeetingRecord(
            id: UUID(), title: "Standup", date: Date(timeIntervalSince1970: 0), duration: 1.5,
            transcript: MeetingTranscript(segments: [seg], duration: 1.5),
            minutes: nil, speakerNames: [:])
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(MeetingRecord.self, from: data)
        XCTAssertEqual(decoded.id, record.id)
        XCTAssertEqual(decoded.transcript.segments.first?.text, "Hi")
    }
}
