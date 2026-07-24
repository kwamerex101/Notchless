import AppKit

/// A borderless, non-activating, transparent panel that floats above the menu
/// bar and hosts the notch UI. Click-through for now (Phase 1); hit-testing for
/// hover/click arrives in Phase 2.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configureAsOverlayPanel()
    }

    /// Whether the panel may currently become key. False by default (pure
    /// pass-through overlay); flipped true only while an in-notch text field is
    /// being edited, so quick-add/quick-log can receive keystrokes without the
    /// panel ever stealing input while collapsed.
    var wantsKey = false

    override var canBecomeKey: Bool { wantsKey }
    override var canBecomeMain: Bool { false }
}
