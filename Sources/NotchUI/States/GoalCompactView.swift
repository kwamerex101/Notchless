import SwiftUI

/// Compact idle cue for the pinned goal: a progress ring + percentage on the
/// left, the abbreviated target on the right. Reads GoalStore.shared directly.
struct GoalCompactView: View {
    @ObservedObject private var store = GoalStore.shared

    /// Kept as an alias for `GoalExpandedView` (outside this restyle's scope),
    /// which still references it. Points at the shared token now.
    static let lightGreen = NotchTheme.positive

    /// The leading ring + percent.
    struct Ring: View {
        let fraction: Double
        var body: some View {
            ZStack {
                Circle().stroke(NotchTheme.track, lineWidth: 2.5)
                Circle().trim(from: 0, to: max(0.001, fraction))
                    .stroke(NotchTheme.positive, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
            .animation(NotchMotion.fill, value: fraction)
        }
    }

    private var symbol: String { SettingsStore.shared.currencySymbol }

    @ViewBuilder var leading: some View {
        if let g = store.pinned {
            HStack(spacing: 6) {
                Ring(fraction: g.fraction)
                Text("\(g.percent)%")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(NotchTheme.positive)
                    .contentTransition(.numericText())
                    .animation(NotchMotion.quick, value: g.percent)
            }
        } else {
            Image(systemName: "target").font(.system(size: 13, weight: .semibold)).foregroundStyle(NotchTheme.textPrimary)
        }
    }

    @ViewBuilder var trailing: some View {
        if let g = store.pinned {
            Text(goalAbbreviate(g.target, symbol: symbol))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchTheme.textBrightSecondary)
        }
    }

    // Standalone body (used by DebugRender previews).
    var body: some View {
        HStack { leading; Spacer(minLength: 0); trailing }
    }
}
