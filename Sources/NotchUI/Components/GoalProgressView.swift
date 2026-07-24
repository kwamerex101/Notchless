import SwiftUI

/// Sizing for `GoalProgressView` — lets the same card render at notch-drawer
/// scale or larger inside a floating widget without duplicating its behavior.
struct GoalProgressMetrics {
    var nameSize: CGFloat
    var pinButtonSize: CGFloat
    var ringSize: CGFloat
    var heroSize: CGFloat
    var ofSize: CGFloat
    var paceSize: CGFloat
    var metaLabelSize: CGFloat
    var metaValueSize: CGFloat
    var breakdownSize: CGFloat
    var padding: CGFloat
    var cornerRadius: CGFloat
    var spacing: CGFloat

    /// Sizing used inside the notch drawer.
    static let notch = GoalProgressMetrics(
        nameSize: 12, pinButtonSize: 11, ringSize: 42, heroSize: 19, ofSize: 11,
        paceSize: 11, metaLabelSize: 9, metaValueSize: 11, breakdownSize: 10,
        padding: 12, cornerRadius: 12, spacing: 6)

    /// Sizing used inside a floating widget card, read at arm's length rather
    /// than at the notch's close range.
    static let widget = GoalProgressMetrics(
        nameSize: 14, pinButtonSize: 13, ringSize: 54, heroSize: 26, ofSize: 12,
        paceSize: 12, metaLabelSize: 10, metaValueSize: 13, breakdownSize: 12,
        padding: 16, cornerRadius: 16, spacing: 8)
}

/// One goal's card in the ring-led hierarchy: a progress ring carrying the
/// percentage, the saved amount as the hero, a one-line pace verdict, then a
/// quiet meta grid (deadline + catch-up rate) and the per-label breakdown. The
/// single accent is `positive` (green = ahead); the currency symbol appears
/// only on the hero. Owns the pin toggle (`GoalStore.setPinned`); everything
/// else is read-only — contributions are logged from the quick-log row.
struct GoalProgressView: View {
    @ObservedObject private var store = GoalStore.shared
    let goal: Goal
    var metrics: GoalProgressMetrics = .notch
    let symbol: String
    var now: Date = Date()

    private var isPinned: Bool { goal.id == store.pinnedID }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing + 2) {
            header
            Rectangle().fill(NotchTheme.hairline).frame(height: 1)
            metaGrid
            if !goal.breakdown.isEmpty { breakdown }
        }
        .padding(metrics.padding)
        .background(RoundedRectangle(cornerRadius: metrics.cornerRadius).fill(NotchTheme.inset))
    }

    /// Ring + name/hero/pace + pin toggle.
    private var header: some View {
        HStack(alignment: .center, spacing: metrics.spacing + 4) {
            ring
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.name)
                    .font(.system(size: metrics.nameSize, weight: .medium))
                    .foregroundStyle(NotchTheme.textBrightSecondary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(goalFormatAmountPrefixed(goal.current, symbol: symbol))
                        .font(.system(size: metrics.heroSize, weight: .semibold).monospacedDigit())
                        .foregroundStyle(NotchTheme.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text("of \(goalFormatPlain(goal.target))")
                        .font(.system(size: metrics.ofSize).monospacedDigit())
                        .foregroundStyle(NotchTheme.textSecondary)
                        .lineLimit(1)
                }
                Text(GoalPacePresentation.paceLabelBare(for: goal, now: now))
                    .font(.system(size: metrics.paceSize, weight: .medium))
                    .foregroundStyle(GoalPacePresentation.color(for: goal, now: now))
            }
            Spacer(minLength: 0)
            pinButton
        }
    }

    private var ring: some View {
        let lw = max(3, metrics.ringSize * 0.11)
        return ZStack {
            Circle().stroke(NotchTheme.ringTrack, lineWidth: lw)
            Circle().trim(from: 0, to: max(0.001, goal.fraction))
                .stroke(NotchTheme.positive, style: StrokeStyle(lineWidth: lw, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(goal.percent)%")
                .font(.system(size: metrics.ringSize * 0.28, weight: .semibold).monospacedDigit())
                .foregroundStyle(NotchTheme.textPrimary)
        }
        .frame(width: metrics.ringSize, height: metrics.ringSize)
        .animation(NotchMotion.fill, value: goal.fraction)
    }

    private var pinButton: some View {
        Button { store.setPinned(goal.id) } label: {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.system(size: metrics.pinButtonSize))
                .foregroundStyle(isPinned ? NotchTheme.recording : NotchTheme.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPinned ? "Pinned goal" : "Pin goal")
    }

    private var metaGrid: some View {
        HStack(alignment: .top, spacing: metrics.spacing) {
            metaCell("Deadline", goalFormatDate(goal.deadline), alignment: .leading)
            Spacer(minLength: 0)
            if let need = goal.neededPerMonth(now: now) {
                metaCell("To stay on track", "\(goalFormatPlain(need))/mo", alignment: .trailing)
            }
        }
    }

    private func metaCell(_ label: String, _ value: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: metrics.metaLabelSize, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(NotchTheme.textTertiary)
            Text(value)
                .font(.system(size: metrics.metaValueSize, weight: .medium).monospacedDigit())
                .foregroundStyle(NotchTheme.textBrightSecondary)
        }
    }

    private var breakdown: some View {
        VStack(spacing: 3) {
            ForEach(goal.breakdown, id: \.label) { item in
                HStack {
                    Text(item.label)
                        .font(.system(size: metrics.breakdownSize))
                        .foregroundStyle(NotchTheme.textSecondary).lineLimit(1)
                    Spacer()
                    Text(goalFormatAmount(item.total, symbol: symbol))
                        .font(.system(size: metrics.breakdownSize).monospacedDigit())
                        .foregroundStyle(NotchTheme.textTertiary)
                }
            }
        }
    }
}
