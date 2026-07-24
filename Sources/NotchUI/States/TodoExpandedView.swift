import SwiftUI

/// The expanded task panel: a reorderable checklist with per-row check-off
/// (toggles done, strike-through, stays in the list) and a quick-add field at
/// the bottom. Completed tasks are cleared in bulk via the header's "Clear done".
struct TodoExpandedView: View {
    @ObservedObject private var store = TodoStore.shared
    @ObservedObject private var widgets = WidgetController.shared
    let metrics: NotchMetrics

    @State private var newTitle = ""
    @FocusState private var addFocused: Bool
    @Environment(\.notchKeyFocus) private var keyFocus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Tasks").notchSectionHeader()
                Spacer()
                if store.completedCount > 0 {
                    Button("Clear done") { withAnimation(NotchMotion.quick) { store.clearCompleted() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                if store.openCount > 0 {
                    Text("\(store.openCount) left")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                popOutButton
            }

            if store.items.isEmpty {
                Text("All clear ✓ — add a task below.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                List {
                    ForEach(store.items) { todo in
                        TodoRowView(todo: todo, metrics: .notch)
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

    /// Pops the To-Dos widget open/closed. Tinted green — matching the
    /// checkmark/progress accent used elsewhere — while the widget is open.
    private var popOutButton: some View {
        Button { widgets.toggle(.todos) } label: {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(widgets.isOpen(.todos) ? .green : .white.opacity(0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(widgets.isOpen(.todos) ? "Close Tasks widget" : "Open Tasks widget")
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
