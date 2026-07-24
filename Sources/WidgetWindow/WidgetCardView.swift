import AppKit
import SwiftUI

/// Rounded floating card chrome every widget wraps its content in: a title
/// strip (also the drag handle) plus the widget's content below it. Matches
/// the notch's dark aesthetic (`NotchDesign`, `ClassicHUDView`) rather than
/// inventing a new background treatment, but adds a shadow — unlike the
/// notch, a widget floats over arbitrary desktop content and needs to read
/// as raised above it.
struct WidgetCardView<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder var content: () -> Content

    private static var cornerRadius: CGFloat { 16 }

    var body: some View {
        VStack(spacing: 0) {
            titleStrip
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.9))
        )
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
    }

    private var titleStrip: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        // Drag handle sits BEHIND the row (as a background, not a greedy ZStack
        // sibling) so the row's natural height governs the strip. A click on the
        // close button still hits the button — it's in front of this handle.
        .background(WindowDragHandle())
    }
}

/// Marks a view whose clicks must NOT borrow keyboard focus through
/// `WidgetPanel.sendEvent` — today just the title-strip drag handle below,
/// whose `mouseDown` hands the event straight to `performDrag(with:)`
/// instead of letting it participate in the normal click-to-focus path.
protocol NonBorrowingClickTarget: NSView {}

/// Forwards `mouseDown` on the title strip to `performDrag(with:)` so the
/// widget panel can be repositioned by its title strip only. Deliberately
/// not `isMovableByWindowBackground` — see `WidgetPanel`'s init comment:
/// background-movability would fight the todo list's drag-to-reorder gesture
/// everywhere else in the card.
private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleView { DragHandleView() }
    func updateNSView(_ nsView: DragHandleView, context: Context) {}

    final class DragHandleView: NSView, NonBorrowingClickTarget {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
