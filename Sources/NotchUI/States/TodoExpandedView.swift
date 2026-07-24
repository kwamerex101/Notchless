import SwiftUI

/// The expanded task panel: a reorderable checklist with per-row check-off
/// (toggles done, strike-through, stays in the list) and a quick-add field at
/// the bottom. Completed tasks are cleared in bulk via the header's "Clear done".
struct TodoExpandedView: View {
    @ObservedObject private var store = TodoStore.shared
    let metrics: NotchMetrics

    @State private var newTitle = ""
    @FocusState private var addFocused: Bool
    @Environment(\.notchKeyFocus) private var keyFocus

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("Tasks").notchSectionHeader()
                Spacer()
                if store.completedCount > 0 {
                    Button("Clear done") { withAnimation(NotchMotion.quick) { store.clearCompleted() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotchTheme.textSecondary)
                }
                if store.openCount > 0 {
                    Text("\(store.openCount) left")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotchTheme.textSecondary)
                }
            }

            if store.items.isEmpty {
                Text("All clear ✓ — add a task below.")
                    .font(.system(size: 12)).foregroundStyle(NotchTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                List {
                    ForEach(store.items) { todo in
                        row(todo)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                    }
                    .onMove { store.move(from: $0, to: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .animation(NotchMotion.quick, value: store.items)
            }

            quickAdd
        }
        .padding(.top, metrics.notchHeight + 10)
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { keyFocus(true); addFocused = true }
        .onDisappear { keyFocus(false) }
    }

    private func row(_ todo: Todo) -> some View {
        HStack(spacing: 10) {
            Button { withAnimation(NotchMotion.micro) { store.setDone(todo.id, !todo.isDone) } } label: {
                Image(systemName: todo.isDone ? "checkmark.circle" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(todo.isDone ? NotchTheme.positive : NotchTheme.textPrimary.opacity(0.6))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(NotchButtonStyle())
            .accessibilityLabel(todo.isDone ? "Mark incomplete" : "Complete task")

            Text(todo.title)
                .font(.system(size: 13))
                .foregroundStyle(todo.isDone ? NotchTheme.textSecondary : NotchTheme.textPrimary)
                .strikethrough(todo.isDone, color: NotchTheme.textSecondary)
                .animation(.easeInOut(duration: 0.15), value: todo.isDone)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Read-only signals (checking/editing happens in Settings).
            if todo.subtaskProgress.total > 0 {
                Text("\(todo.subtaskProgress.done)/\(todo.subtaskProgress.total)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(NotchTheme.textSecondary)
            }
            if todo.hasNotes {
                Image(systemName: LinkDetector.links(in: todo.notes).isEmpty ? "note.text" : "link")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTheme.textSecondary)
            }
        }
    }

    private var quickAdd: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 14)).foregroundStyle(NotchTheme.textSecondary)
            TextField("Add a task…", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(NotchTheme.textPrimary)
                .focused($addFocused)
                .onSubmit(submit)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: NotchDesign.chipRadius).fill(NotchTheme.inset))
    }

    private func submit() {
        store.add(newTitle)
        newTitle = ""
        addFocused = true
    }
}
