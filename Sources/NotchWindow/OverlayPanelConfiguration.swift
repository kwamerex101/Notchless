import AppKit

extension NSPanel {
    /// Applies the window-server configuration shared by every Notchless
    /// overlay panel: borderless, non-activating, transparent, floating above
    /// normal windows, pass-through to mouse events by default, and present
    /// on every Space (including full-screen spaces, outside Mission
    /// Control's window cycling).
    ///
    /// Callers are expected to have already initialized the panel with
    /// `styleMask: [.borderless, .nonactivatingPanel]`, `backing: .buffered`,
    /// `defer: false` (identical across panels, but part of the designated
    /// initializer so it can't be moved here), and to apply any panel-specific
    /// configuration after calling this.
    func configureAsOverlayPanel() {
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true         // pass-through by default; NotchMouseTracker
                                          // flips this to false only over the notch
        acceptsMouseMovedEvents = true
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }
}
