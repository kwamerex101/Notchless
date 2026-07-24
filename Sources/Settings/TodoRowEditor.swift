import SwiftUI
import AppKit

/// One task's expanded editor in the Settings Tasks pane: its subtasks
/// (add / check / rename / delete / reorder) and a notes field with clickable
/// domain chips for any URLs. Reads/writes `TodoStore.shared`.
struct TodoRowEditor: View {
    @ObservedObject private var store = TodoStore.shared
    let todoID: UUID
    @State private var newSubtask = ""

    private var todo: Todo? { store.items.first { $0.id == todoID } }

    var body: some View {
        if let todo {
            VStack(alignment: .leading, spacing: 8) {
                subtaskList(todo)
                addSubtaskField
                CardDivider()
                notesSection(todo)
            }
            .padding(.leading, 8)
            .padding(.vertical, 4)
        }
    }

    private func subtaskList(_ todo: Todo) -> some View {
        ForEach(Array(todo.subtasks.enumerated()), id: \.element.id) { index, sub in
            HStack(spacing: 8) {
                Button { store.toggleSubtask(sub.id, in: todoID) } label: {
                    Image(systemName: sub.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(sub.isDone ? SettingsTheme.statusGranted : SettingsTheme.textSecondary)
                }.buttonStyle(.plain)

                FlatTextField(placeholder: "Subtask", text: subtaskBinding(sub))
                    .strikethrough(sub.isDone)
                    .opacity(sub.isDone ? 0.6 : 1)

                // Up/down reorder (a CardGroup VStack isn't a reorderable List;
                // buttons call the same moveSubtask the store exposes).
                Button { move(index, by: -1, in: todo) } label: {
                    Image(systemName: "chevron.up")
                }.buttonStyle(.plain).disabled(index == 0).foregroundStyle(SettingsTheme.textSecondary)
                Button { move(index, by: 1, in: todo) } label: {
                    Image(systemName: "chevron.down")
                }.buttonStyle(.plain).disabled(index == todo.subtasks.count - 1).foregroundStyle(SettingsTheme.textSecondary)

                Button { store.removeSubtask(sub.id, from: todoID) } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(SettingsTheme.textSecondary)
                }.buttonStyle(.plain)
            }
            .font(.system(size: 13))
        }
    }

    private var addSubtaskField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle").foregroundStyle(SettingsTheme.textSecondary)
            FlatTextField(placeholder: "Add subtask…", text: $newSubtask) {
                store.addSubtask(to: todoID, title: newSubtask)
                newSubtask = ""
            }
        }
    }

    private func notesSection(_ todo: Todo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes").font(.system(size: 11)).foregroundStyle(SettingsTheme.textSecondary)
            TextEditor(text: notesBinding)
                .font(.system(size: 13))
                .foregroundStyle(SettingsTheme.text)
                .frame(minHeight: 54)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SettingsTheme.insetField))

            let links = LinkDetector.links(in: todo.notes)
            if !links.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 90), spacing: 6, alignment: .leading)],
                    alignment: .leading, spacing: 6
                ) {
                    ForEach(links, id: \.url) { link in
                        Button { NSWorkspace.shared.open(link.url) } label: {
                            Label(link.domain, systemImage: "link")
                                .font(.system(size: 11))
                                .foregroundStyle(SettingsTheme.text)
                                .lineLimit(1)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(SettingsTheme.controlChip))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// SwiftUI move offsets: moving an item DOWN by one needs `to: index + 2`.
    private func move(_ index: Int, by delta: Int, in todo: Todo) {
        let target = delta < 0 ? index - 1 : index + 2
        store.moveSubtask(in: todoID, from: IndexSet(integer: index), to: target)
    }

    private func subtaskBinding(_ sub: Subtask) -> Binding<String> {
        Binding(
            get: {
                store.items.first { $0.id == todoID }?
                    .subtasks.first { $0.id == sub.id }?.title ?? sub.title
            },
            set: { store.updateSubtaskTitle(sub.id, in: todoID, to: $0) }
        )
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { store.items.first { $0.id == todoID }?.notes ?? "" },
            set: { store.updateNotes(of: todoID, to: $0) }
        )
    }
}
