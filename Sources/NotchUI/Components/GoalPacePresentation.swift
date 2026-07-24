import SwiftUI

/// Presentation for `Goal.pace(now:)` — label and color, shared between the
/// notch's expanded view and (later) the goal widget. Pure functions of an
/// explicit `now` (never `Date()` internally) so they're deterministically
/// testable.
enum GoalPacePresentation {
    static func label(for goal: Goal, now: Date, symbol: String) -> String {
        switch goal.pace(now: now) {
        case .onTrack: return "On track"
        case .ahead(let d): return "Ahead \(goalAbbreviate(d, symbol: symbol))"
        case .behind(let d): return "Behind \(goalAbbreviate(d, symbol: symbol))"
        case .overdue: return "Overdue"
        }
    }

    static func color(for goal: Goal, now: Date) -> Color {
        switch goal.pace(now: now) {
        case .onTrack: return .white.opacity(0.6)
        case .ahead: return .green
        case .behind: return .orange
        case .overdue: return .red
        }
    }
}
