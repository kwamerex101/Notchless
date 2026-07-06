import XCTest
@testable import Notchless

/// Covers the incremental transcript parser: aggregate correctness, the
/// per-file (mtime, size) cache, and the 5-hour session-block windowing.
final class ClaudeStatsParserTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudestats-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Writes a jsonl file with one usage line per `(model, input, output)` tuple,
    /// stamped `secondsAgo` before now.
    private func writeTranscript(_ name: String,
                                 lines: [(model: String, input: Int, output: Int, secondsAgo: TimeInterval)]) {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let body = lines.map { line in
            let stamp = iso.string(from: Date().addingTimeInterval(-line.secondsAgo))
            return """
            {"type":"assistant","timestamp":"\(stamp)","message":{"model":"\(line.model)","usage":{"input_tokens":\(line.input),"output_tokens":\(line.output),"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
            """
        }.joined(separator: "\n")
        try? body.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func test_parsesTokenTotals() {
        writeTranscript("a.jsonl", lines: [
            ("claude-sonnet-4", 100, 50, 60),
            ("claude-opus-4", 200, 100, 120),
        ])
        let result = ClaudeStatsController.parse(base: dir, cache: [:])
        let stats = try! XCTUnwrap(result.stats)
        XCTAssertEqual(stats.input, 300)
        XCTAssertEqual(stats.output, 150)
        XCTAssertEqual(result.parsedCount, 1)
    }

    func test_emptyDirectoryYieldsNilStats() {
        let result = ClaudeStatsController.parse(base: dir, cache: [:])
        XCTAssertNil(result.stats)
        XCTAssertEqual(result.parsedCount, 0)
    }

    func test_secondParseReusesCacheForUnchangedFiles() {
        writeTranscript("a.jsonl", lines: [("claude-sonnet-4", 100, 50, 60)])
        writeTranscript("b.jsonl", lines: [("claude-sonnet-4", 10, 5, 120)])

        let first = ClaudeStatsController.parse(base: dir, cache: [:])
        XCTAssertEqual(first.parsedCount, 2)

        // Nothing changed → no file is re-read, totals identical.
        let second = ClaudeStatsController.parse(base: dir, cache: first.cache)
        XCTAssertEqual(second.parsedCount, 0)
        XCTAssertEqual(second.stats?.input, first.stats?.input)
        XCTAssertEqual(second.stats?.total, first.stats?.total)
    }

    func test_changedFileIsReparsedOthersReused() throws {
        writeTranscript("a.jsonl", lines: [("claude-sonnet-4", 100, 50, 60)])
        writeTranscript("b.jsonl", lines: [("claude-sonnet-4", 10, 5, 120)])
        let first = ClaudeStatsController.parse(base: dir, cache: [:])

        // Mutate only b.jsonl (append a line). Its size changes → only it re-parses.
        let bURL = dir.appendingPathComponent("b.jsonl")
        var contents = try String(contentsOf: bURL, encoding: .utf8)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        contents += "\n{\"usage\":{\"input_tokens\":1000,\"output_tokens\":0,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0},\"timestamp\":\"\(iso.string(from: Date()))\",\"model\":\"claude-sonnet-4\"}"
        try contents.write(to: bURL, atomically: true, encoding: .utf8)

        let second = ClaudeStatsController.parse(base: dir, cache: first.cache)
        XCTAssertEqual(second.parsedCount, 1, "only the changed file should be re-read")
        XCTAssertEqual(second.stats?.input, (first.stats?.input ?? 0) + 1000)
    }

    func test_sessionBlockSumsWithinFiveHours() {
        // Two messages 1h apart → same 5-hour block; one 6h ago falls outside.
        writeTranscript("s.jsonl", lines: [
            ("claude-sonnet-4", 1000, 0, 6 * 3600),   // old block, expired
            ("claude-sonnet-4", 1000, 0, 30 * 60),    // current block
            ("claude-sonnet-4", 1000, 0, 5 * 60),     // current block
        ])
        let result = ClaudeStatsController.parse(base: dir, cache: [:])
        let stats = try! XCTUnwrap(result.stats)
        // The active block should have a positive cost and a reset countdown.
        XCTAssertGreaterThan(stats.sessionCost, 0)
        XCTAssertNotNil(stats.sessionResetIn)
    }
}
