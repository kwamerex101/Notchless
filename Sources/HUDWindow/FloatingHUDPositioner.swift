import CoreGraphics
import Foundation

/// Pure geometry for placing the floating HUD panel at one of the 9
/// `HUDPosition`s within a given screen frame. Screen/window frames are
/// bottom-left origin (AppKit convention): y increases upward, so "top"
/// positions use high y (near `maxY`) and "bottom" positions use low y
/// (near `minY`).
enum FloatingHUDPositioner {
    /// Frame (bottom-left origin) placing `hudSize` at `position` inside
    /// `screenFrame`, kept `inset` points from the edges it hugs. `.center`
    /// (and the horizontal/vertical "middle" axis in general) ignores inset
    /// and centers on that axis instead.
    static func frame(for position: HUDPosition, hudSize: CGSize,
                       in screenFrame: NSRect, inset: CGFloat) -> NSRect {
        let x: CGFloat
        switch position {
        case .left, .topLeft, .bottomLeft:
            x = screenFrame.minX + inset
        case .right, .topRight, .bottomRight:
            x = screenFrame.maxX - hudSize.width - inset
        case .top, .center, .bottom:
            x = screenFrame.midX - hudSize.width / 2
        }

        let y: CGFloat
        switch position {
        case .topLeft, .top, .topRight:
            y = screenFrame.maxY - hudSize.height - inset
        case .bottomLeft, .bottom, .bottomRight:
            y = screenFrame.minY + inset
        case .left, .center, .right:
            y = screenFrame.midY - hudSize.height / 2
        }

        return NSRect(origin: CGPoint(x: x, y: y), size: hudSize)
    }
}
