import SwiftUI

/// Contribution entry for the pinned goal. Collapsed, it is a single
/// "+ Add to <goal>" trigger; tapped, it opens the input state — a large amount
/// field, quick-add chips, a label, and Cancel/Add. The parent hides its goal
/// list while `expanded` so the input state has room (the notch drawer is
/// short). Contribution rules mirror the old inline quick-log: a positive
/// amount and a non-empty label, logged onto `GoalStore.pinned`.
struct GoalQuickLogView: View {
    @ObservedObject private var store = GoalStore.shared
    let symbol: String
    var large: Bool = false
    @Binding var expanded: Bool

    @State private var amountText = ""
    @State private var labelText = ""
    @FocusState private var amountFocused: Bool

    private var focused: Goal? { store.pinned }
    private let quickAdds: [Decimal] = [500, 1_000, 5_000]

    private var titleSize: CGFloat { large ? 13 : 12 }
    private var amountSize: CGFloat { large ? 34 : 26 }
    private var controlSize: CGFloat { large ? 13 : 12 }

    var body: some View {
        Group {
            if expanded, let goal = focused {
                inputState(goal)
            } else {
                trigger
            }
        }
        .animation(NotchMotion.quick, value: expanded)
    }

    // MARK: Collapsed trigger

    private var trigger: some View {
        Button { expanded = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: controlSize, weight: .semibold))
                    .foregroundStyle(NotchTheme.textPrimary)
                Text(focused.map { "Add to \($0.name)" } ?? "Add contribution")
                    .font(.system(size: controlSize, weight: .medium))
                    .foregroundStyle(NotchTheme.textBrightSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, large ? 10 : 8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: NotchDesign.chipRadius).fill(NotchTheme.inset))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(focused == nil)
    }

    // MARK: Input state

    private func inputState(_ goal: Goal) -> some View {
        VStack(spacing: large ? 14 : 10) {
            Text("Add to \(goal.name)")
                .font(.system(size: titleSize, weight: .medium))
                .foregroundStyle(NotchTheme.textBrightSecondary)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(symbol)
                    .font(.system(size: titleSize + 3))
                    .foregroundStyle(NotchTheme.textTertiary)
                TextField("0", text: $amountText)
                    .textFieldStyle(.plain)
                    .font(.system(size: amountSize, weight: .bold).monospacedDigit())
                    .foregroundStyle(NotchTheme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .frame(minWidth: large ? 90 : 64, alignment: .leading)
                    .focused($amountFocused)
                    .onSubmit(submit)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                ForEach(quickAdds, id: \.self) { amt in
                    Button { bump(by: amt) } label: {
                        Text("+\(goalFormatPlain(amt))")
                            .font(.system(size: controlSize).monospacedDigit())
                            .foregroundStyle(NotchTheme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 12).fill(NotchTheme.chip))
                    }
                    .buttonStyle(.plain)
                }
            }

            TextField("Label (e.g. Salary)", text: $labelText)
                .textFieldStyle(.plain)
                .font(.system(size: controlSize))
                .foregroundStyle(NotchTheme.textPrimary)
                .multilineTextAlignment(.center)
                .onSubmit(submit)

            HStack(spacing: 8) {
                actionButton("Cancel", filled: false, enabled: true, action: cancel)
                actionButton("Add", filled: true, enabled: canSubmit, action: submit)
            }
        }
        .padding(large ? 16 : 12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: large ? 16 : 12).fill(NotchTheme.inset))
        .onAppear { DispatchQueue.main.async { amountFocused = true } }
    }

    private func actionButton(_ title: String, filled: Bool, enabled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: controlSize, weight: filled ? .semibold : .medium))
                .foregroundStyle(filled
                    ? (enabled ? Color(hex: 0x0B_15_10) : NotchTheme.textTertiary)
                    : NotchTheme.textBrightSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10)
                    .fill(filled ? (enabled ? NotchTheme.positive : NotchTheme.chip) : NotchTheme.chip))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: Logic

    private var parsedAmount: Decimal {
        Decimal(string: amountText.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private var canSubmit: Bool {
        parsedAmount > 0 && !labelText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func bump(by amount: Decimal) {
        amountText = goalFormatPlain(parsedAmount + amount).replacingOccurrences(of: ",", with: "")
        amountFocused = true
    }

    private func submit() {
        guard let goal = focused, parsedAmount > 0,
              !labelText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation(NotchMotion.fill) {
            _ = store.logContribution(goalID: goal.id, amount: parsedAmount, label: labelText)
        }
        reset()
    }

    private func cancel() { reset() }

    private func reset() {
        amountText = ""
        labelText = ""
        amountFocused = false
        expanded = false
    }
}
