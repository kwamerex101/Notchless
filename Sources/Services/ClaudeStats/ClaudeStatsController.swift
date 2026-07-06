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

    /// One message's usage for windowed cost aggregation.
    private struct Entry { let date: Date; let cost: Double; let tokens: Int }

    /// Walks recent transcript files, summing tokens (for the pie/line) and
    /// estimated cost across time windows (5-hour block, week, day, 30 days).
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
        var entries: [Entry] = []

        for case let url as URL in walker where url.pathExtension == "jsonl" {
            if let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               modified < cutoff { continue }
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }

            contents.enumerateLines { line, _ in
                guard line.contains("\"usage\"") else { return }
                let inTok = intField(line, "input_tokens")
                let outTok = intField(line, "output_tokens")
                let cacheWrite = intField(line, "cache_creation_input_tokens")
                let cacheRead = intField(line, "cache_read_input_tokens")
                let tokens = inTok + outTok + cacheWrite + cacheRead
                guard tokens > 0 else { return }

                input += inTok
                output += outTok
                cache += cacheWrite + cacheRead

                let pricing = ModelPricing.forModel(stringField(line, "model") ?? "")
                let cost = pricing.cost(input: inTok, output: outTok, cacheWrite: cacheWrite, cacheRead: cacheRead)

                if let stamp = stringField(line, "timestamp"), let date = iso.date(from: stamp) {
                    byDay[calendar.startOfDay(for: date), default: 0] += tokens
                    entries.append(Entry(date: date, cost: cost, tokens: tokens))
                }
            }
        }

        guard input + output + cache > 0 else { return nil }

        let now = Date()
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        // 14-day token line.
        var daily: [DayUsage] = []
        for offset in stride(from: 13, through: 0, by: -1) {
            if let day = calendar.date(byAdding: .day, value: -offset, to: today) {
                daily.append(DayUsage(date: day, tokens: byDay[day] ?? 0))
            }
        }

        // Cost windows.
        let weekCost = entries.filter { $0.date >= now.addingTimeInterval(-7 * 86_400) }.reduce(0) { $0 + $1.cost }
        let todayCost = entries.filter { calendar.isDate($0.date, inSameDayAs: today) }.reduce(0) { $0 + $1.cost }
        let yesterdayCost = entries.filter { calendar.isDate($0.date, inSameDayAs: yesterday) }.reduce(0) { $0 + $1.cost }
        let last30Cost = entries.reduce(0) { $0 + $1.cost }
        let (sessionCost, sessionResetIn) = session(from: entries, now: now, calendar: calendar)

        return ClaudeUsageStats(
            input: input, output: output, cache: cache, daily: daily,
            sessionCost: sessionCost, sessionResetIn: sessionResetIn,
            weekCost: weekCost, todayCost: todayCost, yesterdayCost: yesterdayCost, last30Cost: last30Cost)
    }

    /// The current 5-hour "block": blocks start at the first message (floored to
    /// the hour) and last 5 hours; a message past the window opens a new block.
    /// Returns the active block's cost and time until it resets (nil if none).
    private nonisolated static func session(from entries: [Entry], now: Date,
                                            calendar: Calendar) -> (Double, TimeInterval?) {
        let sorted = entries.sorted { $0.date < $1.date }
        let window: TimeInterval = 5 * 3600
        var blockStart: Date?
        var blockCost = 0.0

        for entry in sorted {
            if let start = blockStart, entry.date < start.addingTimeInterval(window) {
                blockCost += entry.cost
            } else {
                blockStart = calendar.date(bySetting: .minute, value: 0, of: entry.date).map {
                    calendar.date(bySetting: .second, value: 0, of: $0) ?? $0
                } ?? entry.date
                blockCost = entry.cost
            }
        }

        guard let start = blockStart else { return (0, nil) }
        let end = start.addingTimeInterval(window)
        return now < end ? (blockCost, end.timeIntervalSince(now)) : (0, nil)
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
