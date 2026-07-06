import SwiftUI

/// The expanded task panel: a reorderable checklist with per-row check-off
/// (strike-through, then auto-remove) and a quick-add field at the bottom.
struct TodoExpandedView: View {
    @ObservedObject private var store = TodoStore.shared
    let metrics: NotchMetrics

    @State private var newTitle = ""
    @FocusState private var addFocused: Bool
    @Environment(\.notchKeyFocus) private var keyFocus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tasks")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                if store.openCount > 0 {
                    Text("\(store.openCount) left")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            if store.items.isEmpty {
                Text("All clear ✓ — add a task below.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
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
                .animation(.easeInOut(duration: 0.25), value: store.items)
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
            Button { store.complete(todo.id) } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(todo.isDone ? .green : .white.opacity(0.85))
            }
            .buttonStyle(.plain)

            Text(todo.title)
                .font(.system(size: 13))
                .foregroundStyle(todo.isDone ? .white.opacity(0.4) : .white)
                .strikethrough(todo.isDone, color: .white.opacity(0.5))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Read-only signals (checking/editing happens in Settings).
            if todo.subtaskProgress.total > 0 {
                Text("\(todo.subtaskProgress.done)/\(todo.subtaskProgress.total)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
            }
            if todo.hasNotes {
                Image(systemName: LinkDetector.links(in: todo.notes).isEmpty ? "note.text" : "link")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private var quickAdd: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 14)).foregroundStyle(.white.opacity(0.5))
            TextField("Add a task…", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .focused($addFocused)
                .onSubmit(submit)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
    }

    private func submit() {
        store.add(newTitle)
        newTitle = ""
        addFocused = true
    }
}
