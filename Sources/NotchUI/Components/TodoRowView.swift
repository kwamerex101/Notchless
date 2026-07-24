import SwiftUI

/// Sizing for `TodoRowView` — lets the same row render at notch-drawer scale
/// or larger inside a floating widget without duplicating the row's behavior.
struct TodoRowMetrics {
    var checkSize: CGFloat
    var titleSize: CGFloat
    var signalSize: CGFloat
    var spacing: CGFloat

    /// Sizing used inside the notch drawer.
    static let notch = TodoRowMetrics(checkSize: 15, titleSize: 13, signalSize: 11, spacing: 10)

    /// Sizing used inside a floating widget card, read at arm's length rather
    /// than at the notch's close range.
    static let widget = TodoRowMetrics(checkSize: 20, titleSize: 16, signalSize: 14, spacing: 13)
}

/// One row of the task checklist: the check-off button (toggles done,
/// strike-through, symbol transition, accessibility label) plus read-only
/// subtask/notes signals (checking/editing those happens in Settings).
struct TodoRowView: View {
    @ObservedObject private var store = TodoStore.shared
    let todo: Todo
    var metrics: TodoRowMetrics = .notch

    var body: some View {
        HStack(spacing: metrics.spacing) {
            Button { withAnimation(NotchMotion.micro) { store.setDone(todo.id, !todo.isDone) } } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: metrics.checkSize, weight: .semibold))
                    .foregroundStyle(todo.isDone ? NotchTheme.positive : NotchTheme.textPrimary.opacity(0.6))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(NotchButtonStyle())
            .accessibilityLabel(todo.isDone ? "Mark incomplete" : "Complete task")

            Text(todo.title)
                .font(.system(size: metrics.titleSize))
                .foregroundStyle(todo.isDone ? NotchTheme.textSecondary : NotchTheme.textPrimary)
                .strikethrough(todo.isDone, color: NotchTheme.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if todo.subtaskProgress.total > 0 {
                Text("\(todo.subtaskProgress.done)/\(todo.subtaskProgress.total)")
                    .font(.system(size: metrics.signalSize, weight: .semibold).monospacedDigit())
                    .foregroundStyle(NotchTheme.textSecondary)
            }
            if todo.hasNotes {
                Image(systemName: LinkDetector.links(in: todo.notes).isEmpty ? "note.text" : "link")
                    .font(.system(size: metrics.signalSize, weight: .semibold))
                    .foregroundStyle(NotchTheme.textSecondary)
            }
        }
    }
}
