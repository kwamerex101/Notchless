import SwiftUI

/// Sizing for `GoalProgressView` — lets the same card render at notch-drawer
/// scale or larger inside a floating widget without duplicating its behavior.
struct GoalProgressMetrics {
    var nameSize: CGFloat
    var pinIndicatorSize: CGFloat
    var pinButtonSize: CGFloat
    var amountSize: CGFloat
    var percentSize: CGFloat
    var paceSize: CGFloat
    var metaSize: CGFloat
    var breakdownSize: CGFloat
    var padding: CGFloat
    var cornerRadius: CGFloat
    var spacing: CGFloat

    /// Sizing used inside the notch drawer.
    static let notch = GoalProgressMetrics(
        nameSize: 12, pinIndicatorSize: 9, pinButtonSize: 10, amountSize: 10, percentSize: 10, paceSize: 10,
        metaSize: 9, breakdownSize: 10, padding: 10, cornerRadius: 8, spacing: 5)

    /// Sizing used inside a floating widget card, read at arm's length rather
    /// than at the notch's close range.
    static let widget = GoalProgressMetrics(
        nameSize: 16, pinIndicatorSize: 12, pinButtonSize: 13, amountSize: 13, percentSize: 13, paceSize: 13,
        metaSize: 12, breakdownSize: 13, padding: 14, cornerRadius: 12, spacing: 7)
}

/// One goal's card: name + pin toggle, progress bar, amount/percent/pace line,
/// deadline + catch-up-rate line, and the per-label breakdown. Owns the pin
/// button's behavior (`GoalStore.setPinned`); everything else is read-only —
/// contributions are logged from the quick-log row, not here.
struct GoalProgressView: View {
    @ObservedObject private var store = GoalStore.shared
    let goal: Goal
    var metrics: GoalProgressMetrics = .notch
    let symbol: String
    var now: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing) {
            HStack {
                if goal.id == store.pinnedID {
                    Image(systemName: "pin.fill").font(.system(size: metrics.pinIndicatorSize)).foregroundStyle(.red)
                }
                Text(goal.name).font(.system(size: metrics.nameSize, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Spacer()
                Button { store.setPinned(goal.id) } label: {
                    Image(systemName: goal.id == store.pinnedID ? "pin.fill" : "pin")
                        .font(.system(size: metrics.pinButtonSize))
                        .foregroundStyle(goal.id == store.pinnedID ? .red : .white.opacity(0.6))
                }.buttonStyle(.plain)
            }
            ProgressView(value: goal.fraction)
                .tint(.green)
                .animation(NotchMotion.fill, value: goal.fraction)
            HStack(spacing: 6) {
                Text("\(goalFormatAmount(goal.current, symbol: symbol)) / \(goalFormatAmount(goal.target, symbol: symbol))")
                    .font(.system(size: metrics.amountSize)).foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1).minimumScaleFactor(0.75)
                Text("\(goal.percent)%")
                    .font(.system(size: metrics.percentSize, weight: .semibold).monospacedDigit())
                    .foregroundStyle(GoalCompactView.lightGreen)
                Spacer()
                Text(GoalPacePresentation.label(for: goal, now: now, symbol: symbol))
                    .font(.system(size: metrics.paceSize, weight: .medium))
                    .foregroundStyle(GoalPacePresentation.color(for: goal, now: now))
            }
            HStack {
                Text("Ends \(goalFormatDate(goal.deadline))")
                    .font(.system(size: metrics.metaSize)).foregroundStyle(.white.opacity(0.45))
                Spacer()
                if let need = goal.neededPerMonth(now: now) {
                    Text("Need \(goalFormatAmount(need, symbol: symbol))/mo")
                        .font(.system(size: metrics.metaSize, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                }
            }
            if !goal.breakdown.isEmpty {
                ForEach(goal.breakdown, id: \.label) { item in
                    HStack {
                        Text(item.label).font(.system(size: metrics.breakdownSize)).foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        Text(goalFormatAmount(item.total, symbol: symbol)).font(.system(size: metrics.breakdownSize)).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .padding(metrics.padding)
        .background(RoundedRectangle(cornerRadius: metrics.cornerRadius).fill(Color.white.opacity(0.06)))
    }
}
