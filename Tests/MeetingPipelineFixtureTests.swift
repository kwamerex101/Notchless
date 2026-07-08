import XCTest
@testable import Notchless

final class MeetingPipelineFixtureTests: XCTestCase {
    func testPipelineProducesOrderedLabeledTranscript() async throws {
        let modelReady = await ParakeetModelStore.shared.isReady
        try XCTSkipUnless(modelReady, "Parakeet model not downloaded")
        let mic = Bundle(for: Self.self).url(forResource: "you", withExtension: "wav")!
        let remote = Bundle(for: Self.self).url(forResource: "remote", withExtension: "wav")!
        let rec = MeetingRecording(micURL: mic, remoteURL: remote, startedAt: Date(), duration: 10)
        let transcript = try await MeetingTranscriptionPipeline().run(rec)
        XCTAssertFalse(transcript.segments.isEmpty)
        // segments are time-ordered
        let starts = transcript.segments.map(\.start)
        XCTAssertEqual(starts, starts.sorted())
        // at least one "you" and one remote speaker present
        XCTAssertTrue(transcript.segments.contains { if case .you = $0.speaker { return true }; return false })
        XCTAssertTrue(transcript.segments.contains { if case .remote = $0.speaker { return true }; return false })
    }
}
