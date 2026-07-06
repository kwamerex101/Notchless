import SwiftUI

/// The expanded goals panel: every active goal with its bar, pace hint, and
/// per-label breakdown, plus a quick-log row for the focused goal.
struct GoalExpandedView: View {
    @ObservedObject private var store = GoalStore.shared
    let metrics: NotchMetrics

    @State private var amountText = ""
    @State private var labelText = ""
    @FocusState private var amountFocused: Bool

    private var symbol: String { SettingsStore.shared.currencySymbol }

    /// The goal the quick-log row targets: the pinned goal (falls back to first).
    private var focused: Goal? { store.pinned }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Goals").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
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
                        ForEach(store.goals) { goal in row(goal) }
                    }
                }
                quickLog
            }
        }
        .padding(.top, metrics.notchHeight + 10)
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func row(_ goal: Goal) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                if goal.id == store.pinnedID {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.yellow)
                }
                Text(goal.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Spacer()
                Button { store.setPinned(goal.id) } label: {
                    Image(systemName: goal.id == store.pinnedID ? "pin.fill" : "pin")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                }.buttonStyle(.plain)
            }
            ProgressView(value: goal.fraction)
                .tint(.green)
                .animation(.easeInOut(duration: 0.5), value: goal.fraction)
            HStack(spacing: 6) {
                Text("\(goalFormatAmount(goal.current, symbol: symbol)) / \(goalFormatAmount(goal.target, symbol: symbol))")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1).minimumScaleFactor(0.75)
                Text("\(goal.percent)%")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(GoalCompactView.lightGreen)
                Spacer()
                Text(paceLabel(goal)).font(.system(size: 10, weight: .medium)).foregroundStyle(paceColor(goal))
            }
            if !goal.breakdown.isEmpty {
                ForEach(goal.breakdown, id: \.label) { item in
                    HStack {
                        Text(item.label).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        Text(goalFormatAmount(item.total, symbol: symbol)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
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
        withAnimation { _ = store.logContribution(goalID: goal.id, amount: amount, label: labelText) }
        amountText = ""; labelText = ""
    }

    private func paceLabel(_ g: Goal) -> String {
        switch g.pace(now: Date()) {
        case .onTrack: return "On track"
        case .ahead(let d): return "Ahead \(goalAbbreviate(d, symbol: symbol))"
        case .behind(let d): return "Behind \(goalAbbreviate(d, symbol: symbol))"
        case .overdue: return "Overdue"
        }
    }

    private func paceColor(_ g: Goal) -> Color {
        switch g.pace(now: Date()) {
        case .onTrack: return .white.opacity(0.6)
        case .ahead: return .green
        case .behind: return .orange
        case .overdue: return .red
        }
    }
}
