import XCTest
import AVFoundation
@testable import Notchless

final class MeetingCaptureServiceTests: XCTestCase {
    func testWAVWriterProducesReadableFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).wav")
        let writer = try WAVWriter(url: url, sampleRate: 16000)
        var samples = [Float](repeating: 0.5, count: 1600)   // 0.1s
        samples.withUnsafeBufferPointer { writer.append($0.baseAddress!, count: $0.count) }
        writer.close()

        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.fileFormat.sampleRate, 16000)
        XCTAssertEqual(file.length, 1600)
        try? FileManager.default.removeItem(at: url)
    }
}
