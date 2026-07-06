import SwiftUI

/// Compact idle cue for the pinned goal: a progress ring + percentage on the
/// left, the abbreviated target on the right. Reads GoalStore.shared directly.
struct GoalCompactView: View {
    @ObservedObject private var store = GoalStore.shared

    /// A light green for the percentage readout.
    static let lightGreen = Color(red: 0.6, green: 0.95, blue: 0.6)

    /// The leading ring + percent.
    struct Ring: View {
        let fraction: Double
        var body: some View {
            ZStack {
                Circle().stroke(Color.white.opacity(0.18), lineWidth: 3)
                Circle().trim(from: 0, to: max(0.001, fraction))
                    .stroke(.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
            .animation(.easeInOut(duration: 0.5), value: fraction)
        }
    }

    private var symbol: String { SettingsStore.shared.currencySymbol }

    @ViewBuilder var leading: some View {
        if let g = store.pinned {
            HStack(spacing: 6) {
                Ring(fraction: g.fraction)
                Text("\(g.percent)%")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Self.lightGreen)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.4), value: g.percent)
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
