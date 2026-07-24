import CoreGraphics

/// Keeps widget frames on a screen that actually exists. Pure geometry, no
/// AppKit — coordinates are AppKit's bottom-left origin throughout, same
/// convention as `NSScreen.frame`/`NSWindow.frame`.
enum WidgetPlacement {
    /// The smallest amount of a frame that must be showing on some screen
    /// for it to count as "visible" and left alone.
    private static let minVisibleWidth: CGFloat = 80
    private static let minVisibleHeight: CGFloat = 40

    /// How far inside `fallback`'s top-left corner a rescued frame is
    /// placed.
    private static let rescueInset: CGFloat = 40

    /// Returns `frame` unchanged when it is sufficiently visible on one of
    /// `screens` (a widget dragged mostly off-screen but still grabbable is
    /// left alone), otherwise a frame moved onto `fallback` (a widget on a
    /// disconnected display is rescued).
    static func clamped(frame: CGRect, screens: [CGRect], fallback: CGRect) -> CGRect {
        let isVisible = screens.contains { screen in
            let intersection = frame.intersection(screen)
            return !intersection.isNull
                && intersection.width >= minVisibleWidth
                && intersection.height >= minVisibleHeight
        }
        if isVisible { return frame }
        return rescue(frame: frame, onto: fallback)
    }

    /// Places `frame` fully inside `fallback`, offset from its top-left
    /// corner by `rescueInset`, preserving `frame`'s size but shrinking it
    /// to fit if it's larger than `fallback`.
    private static func rescue(frame: CGRect, onto fallback: CGRect) -> CGRect {
        let width = min(frame.width, fallback.width)
        let height = min(frame.height, fallback.height)
        let x = fallback.minX + rescueInset
        let y = fallback.maxY - rescueInset - height
        let clampedX = min(max(x, fallback.minX), fallback.maxX - width)
        let clampedY = min(max(y, fallback.minY), fallback.maxY - height)
        return CGRect(x: clampedX, y: clampedY, width: width, height: height)
    }

    /// How far below the top of `screen` a freshly opened widget with no
    /// remembered position sits.
    private static let defaultTopInset: CGFloat = 120

    /// Where a freshly opened widget of `size` goes on `screen` when it has
    /// no remembered position: centred horizontally, `defaultTopInset`
    /// below the top of `screen`.
    static func defaultFrame(size: CGSize, on screen: CGRect) -> CGRect {
        let x = screen.midX - size.width / 2
        let y = screen.maxY - defaultTopInset - size.height
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
