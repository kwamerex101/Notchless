import SwiftUI

/// Floating pop-out for the To-Dos section. Bound to the same `TodoStore` as
/// the notch drawer, so a change here shows up in `TodoExpandedView` in the
/// same frame. Behavior (reorder, clear-done, quick-add) mirrors
/// `TodoExpandedView` exactly; only sizing and chrome differ.
struct TodoWidgetView: View {
    @ObservedObject private var store = TodoStore.shared

    @State private var newTitle = ""
    @FocusState private var addFocused: Bool

    private static let width: CGFloat = 340
    private static let height: CGFloat = 440

    var body: some View {
        WidgetCardView(title: "Tasks", onClose: { WidgetController.shared.close(.todos) }) {
            VStack(alignment: .leading, spacing: 10) {
                header

                if store.items.isEmpty {
                    Text("All clear ✓ — add a task below.")
                        .font(.system(size: 15)).foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    List {
                        ForEach(store.items) { todo in
                            TodoRowView(todo: todo, metrics: .widget)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        }
                        .onMove { store.move(from: $0, to: $1) }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .animation(NotchMotion.quick, value: store.items)
                }

                quickAdd
            }
            .padding(16)
        }
        .frame(width: Self.width, height: Self.height)
        // Unlike TodoExpandedView, the widget doesn't borrow key focus (or
        // jump into the quick-add field) just because it's visible — a
        // widget is persistent, so borrowing on appear would steal the caret
        // from whatever the user was typing in the moment they opened it and
        // hold it for as long as the widget stays open. Focus is borrowed
        // instead when the user actually clicks into the panel, and released
        // when the panel resigns key — see `WidgetPanel.mouseDown`/
        // `resignKey`.
    }

    private var header: some View {
        HStack(spacing: 8) {
            if store.completedCount > 0 {
                Button("Clear done") { withAnimation(NotchMotion.quick) { store.clearCompleted() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            if store.openCount > 0 {
                Text("\(store.openCount) left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var quickAdd: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 16)).foregroundStyle(.white.opacity(0.5))
            TextField("Add a task…", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .focused($addFocused)
                .onSubmit(submit)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.08)))
    }

    private func submit() {
        store.add(newTitle)
        newTitle = ""
        addFocused = true
    }
}
