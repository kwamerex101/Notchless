import SwiftUI

/// Compact idle cue for the pinned goal: a progress ring + percentage on the
/// left, the abbreviated target on the right. Reads GoalStore.shared directly.
struct GoalCompactView: View {
    @ObservedObject private var store = GoalStore.shared

    /// The leading ring + percent.
    struct Ring: View {
        let fraction: Double
        let tint: Color
        var body: some View {
            ZStack {
                Circle().stroke(Color.white.opacity(0.18), lineWidth: 3)
                Circle().trim(from: 0, to: max(0.001, fraction))
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
        }
    }

    private var symbol: String { SettingsStore.shared.currencySymbol }

    @ViewBuilder var leading: some View {
        if let g = store.pinned {
            HStack(spacing: 6) {
                Ring(fraction: g.fraction, tint: g.percent >= 100 ? .green : .white)
                Text("\(g.percent)%")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
        } else {
            Image(systemName: "target").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
        }
    }

    @ViewBuilder var trailing: some View {
        if let g = store.pinned {
            Text(goalAbbreviate(g.target, symbol: symbol))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    // Standalone body (used by DebugRender previews).
    var body: some View {
        HStack { leading; Spacer(minLength: 0); trailing }
    }
}
