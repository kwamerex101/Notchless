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
    var daily: [DayUsage]   // oldest → newest (tokens)

    // Estimated cost windows (USD), from tokens × model pricing.
    var sessionCost: Double         // current 5-hour block
    var sessionResetIn: TimeInterval?   // seconds until the block resets (nil = no active block)
    var weekCost: Double            // last 7 days
    var todayCost: Double
    var yesterdayCost: Double
    var last30Cost: Double

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

    static func money(_ v: Double) -> String {
        String(format: "$%.2f", v)
    }

    /// "5h", "1d 3h", "12m" — a short reset countdown.
    static func countdown(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        let d = s / 86_400, h = (s % 86_400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

/// Per-million-token prices used to estimate cost. Approximate Anthropic list
/// prices; results are labelled as estimates.
struct ModelPricing {
    let input: Double, output: Double, cacheWrite: Double, cacheRead: Double

    static func forModel(_ model: String) -> ModelPricing {
        let m = model.lowercased()
        if m.contains("opus") {
            return ModelPricing(input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.5)
        }
        if m.contains("haiku") {
            return ModelPricing(input: 0.8, output: 4, cacheWrite: 1, cacheRead: 0.08)
        }
        // Sonnet / default.
        return ModelPricing(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.3)
    }

    /// Cost in USD for a message's token counts.
    func cost(input: Int, output: Int, cacheWrite: Int, cacheRead: Int) -> Double {
        (Double(input) * self.input
         + Double(output) * self.output
         + Double(cacheWrite) * self.cacheWrite
         + Double(cacheRead) * self.cacheRead) / 1_000_000
    }
}
