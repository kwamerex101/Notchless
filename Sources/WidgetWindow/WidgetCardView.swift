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

    @State private var gripHover = false

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
        .overlay(alignment: .bottomTrailing) { resizeGrip }
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

    /// Bottom-right resize grip, overlaid on the card after clipping so its
    /// glyph isn't cut off by `clipShape`. Subtle by default, brightening on
    /// hover like a native macOS resize corner; the actual resizing is done
    /// by `ResizeHandle`'s backing `NSView` below, this just draws the glyph
    /// on top of it. Sized and inset to sit entirely within the widgets'
    /// 16pt content padding (`TodoWidgetView`/`GoalWidgetView` both pad their
    /// content by 16pt) — a 14pt hit area inset 2pt reaches 2...16pt from the
    /// corner, so the grip can never overlap a control near the edge.
    private var resizeGrip: some View {
        Image(systemName: "arrow.down.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white.opacity(gripHover ? 0.55 : 0.25))
            .frame(width: 14, height: 14)
            .contentShape(Rectangle())
            .background(ResizeHandle())
            .onHover { gripHover = $0 }
            .padding(2)
            .accessibilityLabel("Resize")
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

/// Resizes the host window from the bottom-right corner, anchoring the
/// top-left in place — the drag handle's resize counterpart. Conforms to
/// `NonBorrowingClickTarget` so a resize drag doesn't borrow key focus
/// either, mirroring `WindowDragHandle` above. Also overrides
/// `mouseDownCanMoveWindow` to false so a drag starting on the grip never
/// triggers the panel's `isMovableByWindowBackground` move — the Goals and
/// Meeting panels are background-movable, and without this override a
/// resize drag on them would instead reposition the whole window.
private struct ResizeHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> ResizeHandleView { ResizeHandleView() }
    func updateNSView(_ nsView: ResizeHandleView, context: Context) {}

    final class ResizeHandleView: NSView, NonBorrowingClickTarget {
        private var initialFrame: CGRect = .zero
        private var initialMouse: CGPoint = .zero
        private var screenBounds: CGRect = .zero

        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            initialFrame = window.frame
            initialMouse = NSEvent.mouseLocation
            // Capture the resize ceiling once, at the drag's start, so it can't
            // jump mid-drag if the grip crosses onto another display (NSWindow.screen
            // tracks whichever screen holds the window's majority). Fall back to the
            // main screen, then to the starting frame (a no-grow cap) if somehow
            // there is no screen — the size must never be left unbounded.
            screenBounds = window.screen?.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? initialFrame
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let current = NSEvent.mouseLocation
            let dx = current.x - initialMouse.x
            let dy = current.y - initialMouse.y
            // Grip is bottom-right: rightward drag widens, downward
            // drag (negative dy in AppKit's upward-y space) heightens.
            let proposed = CGSize(width: initialFrame.width + dx,
                                  height: initialFrame.height - dy)
            let newFrame = WidgetPlacement.resized(
                frame: initialFrame,
                proposedSize: proposed,
                minSize: WidgetPlacement.minimumSize,
                within: screenBounds
            )
            window.setFrame(newFrame, display: true)
        }
    }
}
