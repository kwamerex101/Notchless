import Foundation

/// Parses local Claude Code transcripts (~/.claude/projects/**/*.jsonl) for
/// per-message token usage and publishes aggregated stats to
/// `model.claudeStats`. Parsing runs off the main thread and refreshes on a
/// slow timer since it walks the transcript files.
@MainActor
final class ClaudeStatsController {
    private let model: NotchViewModel
    private var timer: Timer?

    init(model: NotchViewModel) {
        self.model = model
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func refresh() {
        Task.detached(priority: .utility) {
            let stats = Self.parse()
            await MainActor.run { self.model.claudeStats = stats }
        }
    }

    /// Walks recent transcript files and sums token usage overall + per day.
    nonisolated static func parse() -> ClaudeUsageStats? {
        let fm = FileManager.default
        let base = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        guard let walker = fm.enumerator(at: base, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return nil
        }

        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        let iso = ISO8601DateFormatter()
        let calendar = Calendar.current

        var input = 0, output = 0, cache = 0
        var byDay: [Date: Int] = [:]

        for case let url as URL in walker where url.pathExtension == "jsonl" {
            if let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               modified < cutoff { continue }
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }

            contents.enumerateLines { line, _ in
                guard line.contains("\"usage\"") else { return }
                let inTok = intField(line, "input_tokens")
                let outTok = intField(line, "output_tokens")
                let cacheTok = intField(line, "cache_creation_input_tokens") + intField(line, "cache_read_input_tokens")
                guard inTok + outTok + cacheTok > 0 else { return }

                input += inTok
                output += outTok
                cache += cacheTok

                if let stamp = stringField(line, "timestamp"), let date = iso.date(from: stamp) {
                    let day = calendar.startOfDay(for: date)
                    byDay[day, default: 0] += inTok + outTok + cacheTok
                }
            }
        }

        // Fill a contiguous last-14-days series (zeros for quiet days).
        let today = calendar.startOfDay(for: Date())
        var daily: [DayUsage] = []
        for offset in stride(from: 13, through: 0, by: -1) {
            if let day = calendar.date(byAdding: .day, value: -offset, to: today) {
                daily.append(DayUsage(date: day, tokens: byDay[day] ?? 0))
            }
        }

        guard input + output + cache > 0 else { return nil }
        return ClaudeUsageStats(input: input, output: output, cache: cache, daily: daily)
    }

    /// Reads an integer JSON field value. The leading quote in the search key
    /// keeps `input_tokens` from matching inside `cache_..._input_tokens`.
    private nonisolated static func intField(_ line: String, _ key: String) -> Int {
        guard let range = line.range(of: "\"\(key)\":") else { return 0 }
        let digits = line[range.upperBound...].prefix { $0.isNumber }
        return Int(digits) ?? 0
    }

    private nonisolated static func stringField(_ line: String, _ key: String) -> String? {
        guard let range = line.range(of: "\"\(key)\":\"") else { return nil }
        return String(line[range.upperBound...].prefix { $0 != "\"" })
    }
}
