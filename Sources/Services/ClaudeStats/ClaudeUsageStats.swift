import SwiftUI

/// One day's token total for the usage line chart.
struct DayUsage: Identifiable, Equatable {
    let date: Date
    var tokens: Int
    var id: Date { date }
}

/// Aggregated Claude Code token usage parsed from local transcripts.
struct ClaudeUsageStats: Equatable {
    var input: Int
    var output: Int
    var cache: Int          // cache creation + read
    var daily: [DayUsage]   // oldest → newest

    var total: Int { input + output + cache }

    /// Pie slices: input / output / cache.
    var slices: [(label: String, value: Int, color: Color)] {
        [("Input", input, .blue), ("Output", output, .green), ("Cache", cache, .orange)]
    }

    /// Compact human token count, e.g. "1.2M", "340K".
    static func format(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fK", Double(n) / 1_000) }
        return "\(n)"
    }
}
