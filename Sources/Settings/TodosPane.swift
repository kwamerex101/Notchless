import SwiftUI

/// Settings for the notch task list: enable toggle plus full management of the
/// tasks (add, rename, delete, reorder, clear). Shares `TodoStore.shared` with
/// the notch, so edits here reflect live in the notch and vice versa.
struct TodosPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject private var store = TodoStore.shared
    @State private var newTitle = ""
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneHeader(section: .tasks)

            SectionLabel("Notch")
            CardGroup {
                ToggleRow(title: "Show tasks in the notch", isOn: $settings.todosEnabled)
            }
            Text("Your next task rests in the notch when you have open tasks, and disappears when the list is clear. Check tasks off or add new ones from the notch, or manage the full list here.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            SectionLabel("Tasks")
            CardGroup {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(.secondary)
                    TextField("Add a task…", text: $newTitle)
                        .textFieldStyle(.plain)
                        .onSubmit(addTask)
                }
                if !store.items.isEmpty {
                    Divider()
                    // Add / rename / delete here; drag-to-reorder is the notch's
                    // expanded list (a CardGroup isn't a reorderable List, and
                    // order = priority is most useful right where you glance at it).
                    ForEach(store.items) { todo in
                        HStack(spacing: 8) {
                            TextField("Task", text: binding(for: todo))
                                .textFieldStyle(.plain)
                            Spacer()
                            Button {
                                store.remove(todo.id)
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }.buttonStyle(.plain)
                        }
                        if todo.id != store.items.last?.id { Divider() }
                    }
                }
            }

            if !store.items.isEmpty {
                Button("Clear all tasks", role: .destructive) { confirmClear = true }
                    .buttonStyle(.link)
                    .confirmationDialog("Clear all tasks?", isPresented: $confirmClear) {
                        Button("Clear all", role: .destructive) { store.clear() }
                        Button("Cancel", role: .cancel) {}
                    }
            }
            Spacer()
        }
    }

    private func addTask() {
        store.add(newTitle)
        newTitle = ""
    }

    /// A binding that renames the task on edit; empty edits are ignored by
    /// `updateTitle`, so the displayed value falls back to the stored title.
    private func binding(for todo: Todo) -> Binding<String> {
        Binding(
            get: { store.items.first { $0.id == todo.id }?.title ?? todo.title },
            set: { store.updateTitle(todo.id, to: $0) }
        )
    }
}
