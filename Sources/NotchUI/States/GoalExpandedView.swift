import SwiftUI

/// The expanded goals panel: every active goal with its bar, pace hint, and
/// per-label breakdown, plus a quick-log row for the focused goal.
struct GoalExpandedView: View {
    // GoalStore has no isolated-instance seam (NotchViewModel.goals is a hard
    // alias onto `GoalStore.shared`, iCloud-synced) — this stays on `.shared`
    // deliberately. See DebugStateDump.seed's "Goals/Tasks are the user's
    // real shared stores" note; injecting a seam here would mean giving
    // GoalStore a non-singleton mode, which is out of scope for this pass.
    @ObservedObject private var store = GoalStore.shared
    @ObservedObject private var widgets = WidgetController.shared
    let metrics: NotchMetrics
    /// Injected rather than read from `.shared` so the debug-dump harness's
    /// isolated settings (currency symbol) drive this too.
    let settings: SettingsStore

    @State private var addingContribution = false
    @Environment(\.notchKeyFocus) private var keyFocus

    private var symbol: String { settings.currencySymbol }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Goals").notchSectionHeader()
                Spacer()
                Text("\(store.goals.count) active").font(.system(size: 11)).foregroundStyle(NotchTheme.textSecondary)
                popOutButton
            }

            if store.goals.isEmpty {
                Text("No goals yet — add one in Settings.")
                    .font(.system(size: 12)).foregroundStyle(NotchTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                if !addingContribution {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(store.goals) { goal in
                                GoalProgressView(goal: goal, metrics: .notch, symbol: symbol)
                            }
                        }
                    }
                }
                GoalQuickLogView(symbol: symbol, expanded: $addingContribution)
            }
        }
        .padding(.top, metrics.notchHeight + 10)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { keyFocus(true) }
        .onDisappear { keyFocus(false) }
    }

    /// Pops the Goals widget open/closed. Tinted with the positive token —
    /// matching the progress-bar accent used elsewhere — while the widget
    /// is open.
    private var popOutButton: some View {
        Button { widgets.toggle(.goals) } label: {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(widgets.isOpen(.goals) ? NotchTheme.positive : NotchTheme.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(widgets.isOpen(.goals) ? "Close Goals widget" : "Open Goals widget")
    }

}
