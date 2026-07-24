import SwiftUI

/// Full goal management: enable toggle, currency, add/edit/delete goals,
/// per-goal contribution log, pin selection, and the completed archive.
struct GoalsPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject private var store = GoalStore.shared

    @State private var newName = ""
    @State private var newTarget = ""
    @State private var newDeadline = Date().addingTimeInterval(90 * 86_400)

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            PaneHeader(section: .goals)

            SectionLabel("Goals")
            CardGroup {
                ToggleRow(title: "Enable Goals", isOn: $settings.goalsEnabled)
                CardDivider()
                // Spec calls for two currency chips; the underlying setting is
                // free text (no fixed currency list to pick from), so this
                // stays a pair of inset fields rather than a fabricated picker.
                HStack(spacing: 10) {
                    Text("Currency").font(.system(size: 13)).foregroundStyle(SettingsTheme.text)
                    Spacer()
                    FlatTextField(placeholder: "Code", text: $settings.currencyCode).frame(width: 70)
                    FlatTextField(placeholder: "Symbol", text: $settings.currencySymbol).frame(width: 50)
                }
            }

            SectionLabel("New goal")
            CardGroup {
                FlatTextField(placeholder: "Name (e.g. End-of-year savings)", text: $newName)
                HStack(spacing: 8) {
                    FlatTextField(placeholder: "Target amount", text: $newTarget).frame(width: 140)
                    DatePicker("", selection: $newDeadline, in: Date()..., displayedComponents: .date)
                        .labelsHidden()
                    Spacer()
                    FlatButton(title: "Add") { addGoal() }.disabled(!canAdd)
                }
            }

            if !store.goals.isEmpty {
                SectionLabel("Active goals")
                ForEach(store.goals) { goal in
                    GoalSettingsCard(goal: goal, symbol: settings.currencySymbol)
                }
            }

            if !store.completed.isEmpty {
                SectionLabel("Completed")
                ForEach(store.completed) { goal in completedRow(goal) }
            }
        }
    }

    private var canAdd: Bool {
        !newName.trimmingCharacters(in: .whitespaces).isEmpty && Decimal(string: newTarget) != nil
    }

    private func addGoal() {
        guard let target = Decimal(string: newTarget) else { return }
        _ = store.addGoal(name: newName, target: target, deadline: newDeadline)
        newName = ""; newTarget = ""
    }

    private func completedRow(_ goal: Goal) -> some View {
        CardGroup {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(SettingsTheme.statusGranted)
                Text(goal.name).font(.system(size: 13)).foregroundStyle(SettingsTheme.text)
                Spacer()
                FlatButton(title: "Restore") { store.restore(goal.id) }
                Button { store.deleteGoal(goal.id) } label: {
                    Image(systemName: "trash").foregroundStyle(SettingsTheme.destructiveText)
                }.buttonStyle(.plain)
            }
        }
    }
}

/// One active goal in Settings: progress, a quick-log row to add a contribution
/// (amount + label) without leaving Settings, and the running list of logged
/// contributions (each removable). Mirrors the notch's quick-log.
private struct GoalSettingsCard: View {
    @ObservedObject private var store = GoalStore.shared
    let goal: Goal
    let symbol: String

    @State private var amountText = ""
    @State private var labelText = ""

    /// Re-fetch the live goal so progress + the list update after logging.
    private var live: Goal { store.goals.first { $0.id == goal.id } ?? goal }

    private var canLog: Bool {
        Decimal(string: amountText.trimmingCharacters(in: .whitespaces)) != nil
            && !labelText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        CardGroup {
            HStack(spacing: 8) {
                Text(live.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(SettingsTheme.text)
                Spacer()
                Button { store.setPinned(live.id) } label: {
                    Image(systemName: live.id == store.pinnedID ? "pin.fill" : "pin")
                        .foregroundStyle(live.id == store.pinnedID ? NotchTheme.recording : SettingsTheme.textSecondary)
                }.buttonStyle(.plain).help("Pin as the notch cue")
                Button { store.deleteGoal(live.id) } label: {
                    Image(systemName: "trash").foregroundStyle(SettingsTheme.destructiveText)
                }.buttonStyle(.plain)
            }
            Text("\(goalFormatAmount(live.current, symbol: symbol)) / \(goalFormatAmount(live.target, symbol: symbol)) · \(live.percent)%")
                .font(.system(size: 12)).foregroundStyle(SettingsTheme.textSecondary)

            GoalProgressBar(fraction: live.fraction)

            // Timeline: editable start + end, months left, and the catch-up rate.
            HStack(spacing: 8) {
                dateChip(dateBinding(\.startDate))
                Text("→").font(.system(size: 11)).foregroundStyle(SettingsTheme.textSecondary)
                dateChip(dateBinding(\.deadline))
                Spacer()
                Text("\(Int(live.monthsRemaining(now: Date()).rounded())) mo left")
                    .font(.system(size: 11)).foregroundStyle(SettingsTheme.textSecondary)
            }
            if case .behind = live.pace(now: Date()), let need = live.neededPerMonth(now: Date()) {
                Text("Save \(goalFormatAmount(need, symbol: symbol))/mo to finish on time")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(NotchTheme.warning)
            }

            // Quick-log: add a contribution (amount + label) right here.
            HStack(spacing: 6) {
                FlatTextField(placeholder: "Amount", text: $amountText).frame(width: 80)
                FlatTextField(placeholder: "Label (e.g. Salary, MTN)", text: $labelText, onSubmit: log)
                FlatButton(title: "Log", action: log).disabled(!canLog)
            }

            if !live.contributions.isEmpty {
                CardDivider()
                ForEach(live.contributions) { c in
                    HStack {
                        Text(c.label).font(.system(size: 11)).foregroundStyle(SettingsTheme.text)
                        Spacer()
                        Text(goalFormatAmount(c.amount, symbol: symbol))
                            .font(.system(size: 11)).foregroundStyle(SettingsTheme.textSecondary)
                        Button { store.removeContribution(goalID: live.id, contributionID: c.id) } label: {
                            Image(systemName: "minus.circle").foregroundStyle(SettingsTheme.textSecondary)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func log() {
        guard let amount = Decimal(string: amountText.trimmingCharacters(in: .whitespaces)),
              !labelText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        _ = store.logContribution(goalID: live.id, amount: amount, label: labelText)
        amountText = ""; labelText = ""
    }

    /// A date-picker wrapped in the control-chip look, spec §5 "date chips".
    private func dateChip(_ binding: Binding<Date>) -> some View {
        DatePicker("", selection: binding, displayedComponents: .date)
            .labelsHidden()
            .font(.system(size: 11))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SettingsTheme.controlChip))
    }

    /// Edits a date field on the goal and persists via `updateGoal`.
    private func dateBinding(_ keyPath: WritableKeyPath<Goal, Date>) -> Binding<Date> {
        Binding(
            get: { live[keyPath: keyPath] },
            set: {
                var g = store.goals.first { $0.id == goal.id } ?? goal
                g[keyPath: keyPath] = $0
                store.updateGoal(g)
            }
        )
    }
}

/// The 4pt goal progress bar, spec §5 goal card.
private struct GoalProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(SettingsTheme.switchOff).frame(height: 4)
                Capsule().fill(SettingsTheme.statusGranted)
                    .frame(width: max(0, min(geo.size.width, geo.size.width * fraction)), height: 4)
            }
        }
        .frame(height: 4)
    }
}
