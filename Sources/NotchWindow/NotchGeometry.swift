import AppKit

/// Physical measurements of a screen's notch (or a simulated one), in global
/// AppKit coordinates (bottom-left origin, primary screen at (0,0)).
struct NotchMetrics: Equatable {
    /// Width of the physical notch cutout, in points.
    var notchWidth: CGFloat
    /// Height of the notch / menu-bar band, in points.
    var notchHeight: CGFloat
    /// Global X of the notch centre.
    var notchCenterX: CGFloat
    /// Global Y of the screen's top edge (`frame.maxY`).
    var screenTopY: CGFloat
    /// True when the screen has a real hardware notch.
    var hasRealNotch: Bool

    /// Fallback width used when drawing a simulated notch on a notchless screen.
    static let simulatedWidth: CGFloat = 200
    /// Fallback band height when `safeAreaInsets.top` is unavailable (0).
    static let fallbackHeight: CGFloat = 32
}

enum NotchGeometry {
    /// Measures the notch for a given screen. Uses `auxiliaryTopLeftArea` /
    /// `auxiliaryTopRightArea` to bracket the real cutout; falls back to a
    /// centred simulated notch otherwise.
    static func metrics(for screen: NSScreen) -> NotchMetrics {
        let frame = screen.frame
        let topY = frame.maxY

        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let notchWidth = right.minX - left.maxX
            // Aux areas are reported in the screen's own coordinate space. On the
            // built-in display (origin 0,0) local == global; for a secondary
            // display we lift by the screen origin. If the aux rects are already
            // global on this OS, the raw center already lands inside the frame —
            // so we detect that and avoid double-counting the origin.
            let centerLocalX = (left.maxX + right.minX) / 2
            let rawGlobal = centerLocalX                      // aux treated as global
            let shifted = frame.origin.x + centerLocalX       // aux treated as local
            let centerX = frame.contains(CGPoint(x: rawGlobal, y: frame.midY)) ? rawGlobal : shifted
            let clampedCenterX = min(max(centerX, frame.minX + notchWidth / 2), frame.maxX - notchWidth / 2)

            let insetTop = screen.safeAreaInsets.top
            let height = insetTop > 0 ? insetTop : NotchMetrics.fallbackHeight

            if notchWidth > 1 {
                return NotchMetrics(
                    notchWidth: notchWidth,
                    notchHeight: height,
                    notchCenterX: clampedCenterX,
                    screenTopY: topY,
                    hasRealNotch: true
                )
            }
        }

        // No hardware notch → simulated pill centred on the screen.
        return NotchMetrics(
            notchWidth: NotchMetrics.simulatedWidth,
            notchHeight: NotchMetrics.fallbackHeight,
            notchCenterX: frame.midX,
            screenTopY: topY,
            hasRealNotch: false
        )
    }
}
