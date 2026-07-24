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

    @State private var amountText = ""
    @State private var labelText = ""
    @FocusState private var amountFocused: Bool
    @Environment(\.notchKeyFocus) private var keyFocus

    private var symbol: String { settings.currencySymbol }

    /// The goal the quick-log row targets: the pinned goal (falls back to first).
    private var focused: Goal? { store.pinned }

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
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(store.goals) { goal in
                            GoalProgressView(goal: goal, metrics: .notch, symbol: symbol)
                        }
                    }
                }
                quickLog
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

    // Spec §3 draws this footer as a static "+ Log contribution" row; the real
    // feature needs inline Amount/Label entry, so that behaviour is kept as-is
    // and only the colours/metrics are brought onto the token system.
    private var quickLog: some View {
        HStack(spacing: 6) {
            TextField("Amount", text: $amountText)
                .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(NotchTheme.textPrimary)
                .frame(width: 70).focused($amountFocused)
            TextField("Label", text: $labelText)
                .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(NotchTheme.textPrimary)
                .onSubmit(submit)
            Button(action: submit) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NotchTheme.textBrightSecondary.opacity(0.75))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: NotchDesign.chipRadius).fill(NotchTheme.inset))
    }

    private func submit() {
        guard let goal = focused,
              let amount = Decimal(string: amountText.trimmingCharacters(in: .whitespaces)),
              !labelText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation(NotchMotion.fill) { _ = store.logContribution(goalID: goal.id, amount: amount, label: labelText) }
        amountText = ""; labelText = ""
    }
}
