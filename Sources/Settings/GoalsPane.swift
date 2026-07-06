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
        VStack(alignment: .leading, spacing: 22) {
            PaneHeader(section: .goals)

            CardGroup {
                ToggleRow(title: "Enable Goals", isOn: $settings.goalsEnabled)
                Divider()
                HStack {
                    Text("Currency")
                    Spacer()
                    TextField("Code", text: $settings.currencyCode).frame(width: 70)
                    TextField("Symbol", text: $settings.currencySymbol).frame(width: 50)
                }
            }

            SectionLabel("New goal")
            CardGroup {
                TextField("Name (e.g. End-of-year savings)", text: $newName)
                HStack {
                    TextField("Target amount", text: $newTarget).frame(width: 140)
                    DatePicker("Deadline", selection: $newDeadline, in: Date()..., displayedComponents: .date).labelsHidden()
                    Spacer()
                    Button("Add") { addGoal() }.disabled(!canAdd)
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
            HStack {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text(goal.name)
                Spacer()
                Button("Restore") { store.restore(goal.id) }.buttonStyle(.borderless)
                Button(role: .destructive) { store.deleteGoal(goal.id) } label: {
                    Image(systemName: "trash")
                }.buttonStyle(.borderless)
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
            HStack {
                Text(live.name).font(.headline)
                Spacer()
                Button { store.setPinned(live.id) } label: {
                    Image(systemName: live.id == store.pinnedID ? "pin.fill" : "pin")
                }.buttonStyle(.borderless).help("Pin as the notch cue")
                Button(role: .destructive) { store.deleteGoal(live.id) } label: {
                    Image(systemName: "trash")
                }.buttonStyle(.borderless)
            }
            Text("\(goalFormatAmount(live.current, symbol: symbol)) / \(goalFormatAmount(live.target, symbol: symbol)) · \(live.percent)%")
                .font(.callout).foregroundStyle(.secondary)

            // Quick-log: add a contribution (amount + label) right here.
            HStack(spacing: 6) {
                TextField("Amount", text: $amountText).frame(width: 90)
                TextField("Label (e.g. Salary, MTN)", text: $labelText)
                    .onSubmit(log)
                Button("Log", action: log).disabled(!canLog)
            }

            if !live.contributions.isEmpty {
                Divider()
                ForEach(live.contributions) { c in
                    HStack {
                        Text(c.label)
                        Spacer()
                        Text(goalFormatAmount(c.amount, symbol: symbol)).foregroundStyle(.secondary)
                        Button { store.removeContribution(goalID: live.id, contributionID: c.id) } label: {
                            Image(systemName: "minus.circle")
                        }.buttonStyle(.borderless)
                    }.font(.caption)
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
}
