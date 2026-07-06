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
