import AppKit
import CoreGraphics
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

        // Default level; WidgetController applies the user's desktop-vs-floating
        // preference (the "Widgets on desktop" setting) via applyDesktopPlacement
        // the moment it creates the panel, and again whenever that setting changes.
        level = .floating

        // configureAsOverlayPanel() sets hasShadow = false, right for the
        // notch/HUD (drawn flush to their own edges) but wrong here: this
        // panel is sized exactly to WidgetCardView's rounded card, and that
        // card draws a SwiftUI `.shadow(...)` that falls outside the window
        // bounds and gets clipped to nothing. Turning the AppKit window
        // shadow on draws it around whatever's actually painted — since the
        // window stays transparent (isOpaque = false, clear background),
        // the shadow follows the card's rounded silhouette rather than a
        // rectangular window edge, so the corners still read correctly.
        hasShadow = true

        // Deliberately WITHOUT `.fullScreenAuxiliary`: widgets should not
        // ride over fullscreen apps the way the notch does. Multi-display
        // semantics (does a widget on display B stay visible while display A
        // is fullscreen?) are still pending on-device confirmation — see
        // the fullscreen/multi-display spike in the section-widgets design
        // doc before relying on this across displays.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        // Drag-to-move from anywhere on the card, like a native macOS desktop
        // widget. Excluded for Tasks: its list needs background drags for
        // drag-to-reorder, so it keeps only the title-strip handle. Interactive
        // controls still receive their clicks — AppKit's mouseDownCanMoveWindow
        // returns false for NSControl-backed views, so only inert card
        // background starts a window drag.
        isMovableByWindowBackground = (kind != .todos)
    }

    /// Places the panel on the desktop — above the wallpaper and desktop icons
    /// but BELOW every normal app window and the Dock, like a native macOS
    /// desktop widget — when `onDesktop` is true, or floating above everything
    /// when false. Called when WidgetController creates the panel and whenever
    /// the "Widgets on desktop" preference changes. At desktop level the widget
    /// is hidden behind open windows and shows through when the desktop is
    /// revealed.
    func applyDesktopPlacement(_ onDesktop: Bool) {
        level = onDesktop
            ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
            : .floating
    }

    /// Whether the panel may currently become key. False by default;
    /// flipped true while a widget's text field is being edited, mirroring
    /// `NotchPanel.wantsKey`.
    var wantsKey = false

    override var canBecomeKey: Bool { wantsKey }
    override var canBecomeMain: Bool { false }

    /// Set once by `WidgetController` when it creates the panel. Weak
    /// because the coordinator's own lifetime is owned by `AppDelegate`, not
    /// by the panel — mirroring `holder` on the coordinator side being weak
    /// too, so neither end keeps the other alive.
    weak var focusCoordinator: WidgetFocusCoordinator?

    /// Widgets don't borrow key focus just for being open (see the widget
    /// views' doc comments) — only when the user actually starts
    /// interacting with one. A click is the only way that starts, so borrow
    /// here.
    ///
    /// This overrides `sendEvent`, not `mouseDown`: AppKit dispatches
    /// `mouseDown` straight to the hit-tested view, so a click landing on a
    /// SwiftUI `TextField`/`Button`/`List` (all NSView-backed) never reaches
    /// `NSWindow.mouseDown` at all — it's consumed before the responder
    /// chain would bubble it up. `sendEvent` sees every event before
    /// dispatch, so the borrow fires regardless of which view eats the
    /// click. Then it falls through to `super.sendEvent` so the click still
    /// does its normal job.
    ///
    /// One exception: the title-strip drag handle (`WidgetCardView`'s
    /// `DragHandleView`) calls `performDrag(with:)` directly and never calls
    /// `super.mouseDown`, so without this exclusion every window drag would
    /// also borrow focus and activate the app out from under whatever the
    /// user was working in. A click anywhere else — including a checkbox
    /// tap that isn't text entry — still borrows; scoping the borrow to
    /// text-input views specifically would mean walking SwiftUI's
    /// hosting-view hierarchy looking for an `NSTextView`/`NSTextField`,
    /// which is exactly the kind of hit-testing SwiftUI doesn't expose
    /// reliably (the responder that ends up editing is nested inside
    /// `NSHostingView` machinery, not a plain subview you can spot from
    /// here). The always-borrow-except-drag rule is simple and correct for
    /// the case that actually bit us; its known downside is that clicking
    /// any non-text control in a widget (a checkbox, "Clear done") also
    /// calls `NSApp.activate(ignoringOtherApps:)`, pulling activation away
    /// from the user's frontmost app for an interaction that isn't typing.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !eventHitsDragHandle(event) {
            focusCoordinator?.borrow(self)
        }
        super.sendEvent(event)
    }

    /// Whether `event`'s hit-tested view is the drag handle, or nested
    /// inside it — walks the superview chain because SwiftUI may report an
    /// intermediate hosting view as the direct hit.
    private func eventHitsDragHandle(_ event: NSEvent) -> Bool {
        var view = contentView?.hitTest(event.locationInWindow)
        while let current = view {
            if current is NonBorrowingClickTarget { return true }
            view = current.superview
        }
        return false
    }

    /// Mirrors the borrow above: once this panel is no longer key — the user
    /// clicked back into another app, or another widget/the notch borrowed
    /// focus instead — it has no business holding the borrow. Releasing here
    /// (rather than waiting for the widget to close) is what hands focus
    /// straight back to whatever the user clicked into.
    override func resignKey() {
        super.resignKey()
        focusCoordinator?.release(self)
    }

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
