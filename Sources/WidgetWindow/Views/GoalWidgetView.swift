import SwiftUI

/// Floating pop-out for the Goals section. Bound to the same `GoalStore` as
/// the notch drawer. Quick-log validation/behavior mirrors
/// `GoalExpandedView.submit()` exactly; only sizing and chrome differ.
struct GoalWidgetView: View {
    @ObservedObject private var store = GoalStore.shared

    @State private var amountText = ""
    @State private var labelText = ""
    @FocusState private var amountFocused: Bool

    private var symbol: String { SettingsStore.shared.currencySymbol }

    /// The goal the quick-log row targets: the pinned goal (falls back to first).
    private var focused: Goal? { store.pinned }

    private static let width: CGFloat = 360
    private static let height: CGFloat = 460

    var body: some View {
        WidgetCardView(title: "Goals", onClose: { WidgetController.shared.close(.goals) }) {
            VStack(alignment: .leading, spacing: 10) {
                header

                if store.goals.isEmpty {
                    Text("No goals yet — add one in Settings.")
                        .font(.system(size: 15)).foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(store.goals) { goal in
                                GoalProgressView(goal: goal, metrics: .widget, symbol: symbol)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    quickLog
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: Self.width, height: Self.height)
        // Unlike GoalExpandedView, the widget doesn't borrow key focus on
        // appear — see the comment in `TodoWidgetView.body`. Focus is
        // borrowed on click and released on resign-key, via `WidgetPanel`.
    }

    private var header: some View {
        HStack {
            Spacer()
            Text("\(store.goals.count) active")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
        }
    }

    private var quickLog: some View {
        HStack(spacing: 8) {
            TextField("Amount", text: $amountText)
                .textFieldStyle(.plain).font(.system(size: 14)).foregroundStyle(.white)
                .frame(width: 84).focused($amountFocused)
            TextField("Label", text: $labelText)
                .textFieldStyle(.plain).font(.system(size: 14)).foregroundStyle(.white)
                .onSubmit(submit)
            Button(action: submit) {
                Image(systemName: "plus.circle.fill").foregroundStyle(.white)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.08)))
    }

    private func submit() {
        guard let goal = focused,
              let amount = Decimal(string: amountText.trimmingCharacters(in: .whitespaces)),
              !labelText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation(NotchMotion.fill) { _ = store.logContribution(goalID: goal.id, amount: amount, label: labelText) }
        amountText = ""; labelText = ""
    }
}
