import SwiftUI
import Combine

/// One logged deposit toward a goal. Amount is normally positive; a correction
/// is an explicit negative entry. `label` groups deposits in the breakdown.
struct Contribution: Identifiable, Codable, Equatable {
    let id: UUID
    var amount: Decimal
    var label: String
    var date: Date

    init(id: UUID = UUID(), amount: Decimal, label: String, date: Date) {
        self.id = id
        self.amount = amount
        self.label = label
        self.date = date
    }
}

/// A savings/progress goal: a target amount to reach by a deadline, made up of
/// logged contributions. Pure value type — all math lives here so it is
/// deterministically testable.
struct Goal: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var target: Decimal
    var startDate: Date
    var deadline: Date
    var contributions: [Contribution]
    var completedAt: Date?

    init(id: UUID = UUID(), name: String, target: Decimal, startDate: Date,
         deadline: Date, contributions: [Contribution] = [], completedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.target = target
        self.startDate = startDate
        self.deadline = deadline
        self.contributions = contributions
        self.completedAt = completedAt
    }

    /// Sum of all logged contributions (true total; may exceed target).
    var current: Decimal { contributions.reduce(0) { $0 + $1.amount } }

    /// Progress in 0…1 for bars/rings. Clamped; 0 when target is non-positive.
    var fraction: Double {
        guard target > 0 else { return 0 }
        let ratio = (current as NSDecimalNumber).doubleValue / (target as NSDecimalNumber).doubleValue
        return min(max(ratio, 0), 1)
    }

    /// Whole-number percent for display (0…100).
    var percent: Int { Int((fraction * 100).rounded()) }

    /// Per-label totals, largest first (label ascending as a stable tiebreak).
    var breakdown: [(label: String, total: Decimal)] {
        var totals: [String: Decimal] = [:]
        for c in contributions { totals[c.label, default: 0] += c.amount }
        return totals
            .map { (label: $0.key, total: $0.value) }
            .sorted { $0.total != $1.total ? $0.total > $1.total : $0.label < $1.label }
    }
}

/// Whether a goal is keeping up with the straight-line pace implied by its
/// start→deadline window. `ahead`/`behind` carry the money gap vs. expected.
enum PaceStatus: Equatable {
    case onTrack
    case ahead(Decimal)
    case behind(Decimal)
    case overdue
}

extension Goal {
    /// Compares actual `current` against the linear expected amount for `now`.
    /// A ±2%-of-target dead-band keeps the status from flickering at the line.
    func pace(now: Date) -> PaceStatus {
        if now > deadline && current < target { return .overdue }

        let total = deadline.timeIntervalSince(startDate)
        guard total > 0 else { return .onTrack }
        let elapsed = min(max(now.timeIntervalSince(startDate), 0), total)
        let ratio = elapsed / total
        let expected = target * Decimal(ratio)         // clamped by ratio ∈ 0…1
        let delta = current - expected
        let band = target * Decimal(0.02)

        if abs(delta) <= band { return .onTrack }
        return delta > 0 ? .ahead(delta) : .behind(-delta)
    }
}

/// Full grouped amount with the currency symbol suffixed, no decimals.
/// e.g. goalFormatAmount(42000, symbol: "₵") == "42,000 ₵"
func goalFormatAmount(_ amount: Decimal, symbol: String) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = 0
    f.groupingSeparator = ","
    f.usesGroupingSeparator = true
    let n = f.string(from: amount as NSDecimalNumber) ?? "0"
    return "\(n) \(symbol)"
}

/// Compact amount for the notch cue. 1_000→"1k", 1_500→"1.5k", 1_200_000→"1.2m".
func goalAbbreviate(_ amount: Decimal, symbol: String) -> String {
    let value = (amount as NSDecimalNumber).doubleValue
    func trim(_ d: Double) -> String {
        // one decimal, drop a trailing ".0"
        let s = String(format: "%.1f", d)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
    let body: String
    if abs(value) >= 1_000_000 { body = "\(trim(value / 1_000_000))m" }
    else if abs(value) >= 1_000 { body = "\(trim(value / 1_000))k" }
    else { body = String(Int(value.rounded())) }
    return "\(body) \(symbol)"
}
