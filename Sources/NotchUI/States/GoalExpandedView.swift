import SwiftUI

/// The expanded goals panel: every active goal with its bar, pace hint, and
/// per-label breakdown, plus a quick-log row for the focused goal.
struct GoalExpandedView: View {
    @ObservedObject private var store = GoalStore.shared
    let metrics: NotchMetrics

    @State private var amountText = ""
    @State private var labelText = ""
    @FocusState private var amountFocused: Bool
    @Environment(\.notchKeyFocus) private var keyFocus

    private var symbol: String { SettingsStore.shared.currencySymbol }

    /// The goal the quick-log row targets: the pinned goal (falls back to first).
    private var focused: Goal? { store.pinned }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Goals").notchSectionHeader()
                Spacer()
                Text("\(store.goals.count) active").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }

            if store.goals.isEmpty {
                Text("No goals yet — add one in Settings.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
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

    private var quickLog: some View {
        HStack(spacing: 6) {
            TextField("Amount", text: $amountText)
                .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(.white)
                .frame(width: 70).focused($amountFocused)
            TextField("Label", text: $labelText)
                .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(.white)
                .onSubmit(submit)
            Button(action: submit) {
                Image(systemName: "plus.circle.fill").foregroundStyle(.white)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
    }

    private func submit() {
        guard let goal = focused,
              let amount = Decimal(string: amountText.trimmingCharacters(in: .whitespaces)),
              !labelText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation(NotchMotion.fill) { _ = store.logContribution(goalID: goal.id, amount: amount, label: labelText) }
        amountText = ""; labelText = ""
    }
}
