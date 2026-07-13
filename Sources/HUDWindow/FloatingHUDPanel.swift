import AppKit
import SwiftUI

/// A borderless, non-activating, transparent floating panel that hosts the
/// HUD UI when it is rendered off-notch (Phase 3). Mirrors `NotchPanel`'s
/// window-server-relevant configuration exactly.
///
/// Not yet owned/shown by `AppDelegate` — the presenter that decides
/// notch-vs-floating and wires this panel into the app lifecycle arrives in
/// a later task.
final class FloatingHUDPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Wraps `view` in an `NSHostingView`, sets it as the panel's content,
    /// and sizes the panel to fit the hosted view's intrinsic content size.
    func setContent<V: View>(_ view: V) {
        let host = NSHostingView(rootView: view)
        contentView = host
        host.frame = NSRect(origin: .zero, size: host.intrinsicContentSize)
    }

    /// Positions the panel at `frame` and brings it to the front without
    /// activating the app (matches `NotchPanel`'s orderFrontRegardless flow).
    func show(at frame: NSRect) {
        setFrame(frame, display: true)
        orderFrontRegardless()
    }

    /// Hides the panel without closing/deallocating it.
    func hide() {
        orderOut(nil)
    }
}
