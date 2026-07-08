import XCTest
@testable import Notchless

private struct StubClient: MinutesAPIClient {
    let json: String
    func minutesJSON(prompt: String, model: String) async throws -> String { json }
}

final class MeetingSummarizerTests: XCTestCase {
    func testTranscriptTextLabelsSpeakers() {
        let t = MeetingTranscript(segments: [
            TranscriptSegment(speaker: .you, start: 0, end: 1, text: "Hi", qualityScore: nil),
            TranscriptSegment(speaker: .remote(id: "SPEAKER_00", name: nil), start: 1, end: 2,
                              text: "Hello", qualityScore: nil),
        ], duration: 2)
        let text = MeetingSummarizer.transcriptText(t, speakerNames: ["SPEAKER_00": "Alex"])
        XCTAssertTrue(text.contains("You: Hi"))
        XCTAssertTrue(text.contains("Alex: Hello"))
    }

    func testParsesMinutesJSON() async throws {
        let json = """
        {"summary":"Talked.","decisions":["Ship"],"actionItems":[{"text":"Write","owner":"you"}]}
        """
        let s = MeetingSummarizer(client: StubClient(json: json), model: "claude-sonnet-5")
        let m = try await s.summarize(MeetingTranscript(segments: [], duration: 0), speakerNames: [:])
        XCTAssertEqual(m.summary, "Talked.")
        XCTAssertEqual(m.decisions, ["Ship"])
        XCTAssertEqual(m.actionItems.first?.text, "Write")
        XCTAssertEqual(m.actionItems.first?.owner, .you)
    }
}
