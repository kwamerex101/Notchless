import XCTest
@testable import Notchless

final class MeetingStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testSaveLoadDelete() throws {
        let store = MeetingStore(directory: tempDir())
        let rec = MeetingRecord(id: UUID(), title: "Sync", date: Date(timeIntervalSince1970: 100),
                                duration: 2,
                                transcript: MeetingTranscript(segments: [], duration: 2),
                                minutes: nil, speakerNames: [:])
        try store.save(rec)
        XCTAssertEqual(try store.load().map(\.id), [rec.id])
        try store.delete(id: rec.id)
        XCTAssertTrue(try store.load().isEmpty)
    }

    func testMarkdownContainsMinutesAndLabeledTranscript() {
        let store = MeetingStore(directory: tempDir())
        let seg = TranscriptSegment(speaker: .remote(id: "SPEAKER_00", name: nil),
                                    start: 0, end: 1, text: "Kickoff", qualityScore: nil)
        let rec = MeetingRecord(id: UUID(), title: "Planning", date: Date(timeIntervalSince1970: 0),
                                duration: 1,
                                transcript: MeetingTranscript(segments: [seg], duration: 1),
                                minutes: MeetingMinutes(summary: "We planned.",
                                                        decisions: ["Ship Friday"],
                                                        actionItems: [ActionItem(text: "Draft doc", owner: .you)]),
                                speakerNames: ["SPEAKER_00": "Alex"])
        let md = store.markdown(for: rec)
        XCTAssertTrue(md.contains("# Meeting — Planning"))
        XCTAssertTrue(md.contains("We planned."))
        XCTAssertTrue(md.contains("Ship Friday"))
        XCTAssertTrue(md.contains("**Alex:** Kickoff"))
    }
}
