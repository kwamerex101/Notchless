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
                ForEach(store.goals) { goal in goalCard(goal) }
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

    private func goalCard(_ goal: Goal) -> some View {
        CardGroup {
            HStack {
                Text(goal.name).font(.headline)
                Spacer()
                Button { store.setPinned(goal.id) } label: {
                    Image(systemName: goal.id == store.pinnedID ? "pin.fill" : "pin")
                }.buttonStyle(.borderless).help("Pin as the notch cue")
                Button(role: .destructive) { store.deleteGoal(goal.id) } label: {
                    Image(systemName: "trash")
                }.buttonStyle(.borderless)
            }
            Text("\(goalFormatAmount(goal.current, symbol: settings.currencySymbol)) / \(goalFormatAmount(goal.target, symbol: settings.currencySymbol)) · \(goal.percent)%")
                .font(.callout).foregroundStyle(.secondary)
            if !goal.contributions.isEmpty {
                Divider()
                ForEach(goal.contributions) { c in
                    HStack {
                        Text(c.label)
                        Spacer()
                        Text(goalFormatAmount(c.amount, symbol: settings.currencySymbol)).foregroundStyle(.secondary)
                        Button { store.removeContribution(goalID: goal.id, contributionID: c.id) } label: {
                            Image(systemName: "minus.circle")
                        }.buttonStyle(.borderless)
                    }.font(.caption)
                }
            }
        }
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
