import AppKit
import SwiftUI

/// A borderless, non-activating floating panel that hosts one popped-out
/// section widget (To-Dos, Goals, Meeting). Shares window-server setup with
/// `NotchPanel`/`FloatingHUDPanel` via `configureAsOverlayPanel()`, then
/// diverges where widgets need to behave differently: they accept mouse
/// events, they're draggable, and they stay off fullscreen Spaces.
final class WidgetPanel: NSPanel {
    let kind: WidgetKind

    init(kind: WidgetKind) {
        self.kind = kind
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configureAsOverlayPanel()

        // Widgets are interactive surfaces, not pass-through overlays.
        ignoresMouseEvents = false
        level = .floating

        // Deliberately WITHOUT `.fullScreenAuxiliary`: widgets should not
        // ride over fullscreen apps the way the notch does. Multi-display
        // semantics (does a widget on display B stay visible while display A
        // is fullscreen?) are still pending on-device confirmation — see
        // the fullscreen/multi-display spike in the section-widgets design
        // doc before relying on this across displays.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        // isMovableByWindowBackground stays false (inherited from
        // configureAsOverlayPanel()). Dragging is done by an explicit handle
        // that calls performDrag(with:) instead, because background
        // movability would fight the todo list's drag-to-reorder gesture —
        // AppKit resolves overlapping drag claims via
        // mouseDownCanMoveWindow, whose behavior inside NSHostingView
        // content is version-dependent and historically unreliable.
    }

    /// Whether the panel may currently become key. False by default;
    /// flipped true while a widget's text field is being edited, mirroring
    /// `NotchPanel.wantsKey`.
    var wantsKey = false

    override var canBecomeKey: Bool { wantsKey }
    override var canBecomeMain: Bool { false }

    /// The single hosting view reused across `setContent` calls. Recreating
    /// this mid-gesture (e.g. during a drag-to-reorder that calls
    /// `setContent` on every update) tears out AppKit's in-flight mouse
    /// tracking and interrupts the drag after its first update, so we
    /// update its `rootView` in place instead of replacing `contentView`
    /// each time. Mirrors `FloatingHUDPanel.setContent`.
    private var host: NSHostingView<AnyView>?

    /// Wraps `view` in an `NSHostingView` (reusing the existing one if
    /// present), sets it as the panel's content, and sizes the panel to fit
    /// the hosted view's intrinsic content size.
    func setContent<V: View>(_ view: V) {
        let resolvedHost: NSHostingView<AnyView>
        if let host {
            host.rootView = AnyView(view)
            resolvedHost = host
        } else {
            let newHost = NSHostingView(rootView: AnyView(view))
            contentView = newHost
            host = newHost
            resolvedHost = newHost
        }
        resolvedHost.frame = NSRect(origin: .zero, size: resolvedHost.intrinsicContentSize)
    }
}

extension WidgetPanel: KeyBorrowingPanel {}
