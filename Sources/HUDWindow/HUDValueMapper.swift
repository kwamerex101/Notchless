import CoreGraphics

/// Pure geometry → 0...1 value mappers for the floating HUD's click-drag
/// gesture (Phase 5). No AppKit/SwiftUI dependency so it can be unit-tested
/// in isolation from the live gesture plumbing in `FloatingHUDContentView`.
enum HUDValueMapper {
    /// Horizontal drag position within a bar/pill-shaped HUD → 0...1 (clamped).
    /// Used by the Classic and iOS floating styles.
    static func horizontalFraction(x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(1, max(0, Double(x / width)))
    }

    /// Angular position around a dial → 0...1, measured CLOCKWISE from the
    /// TOP (12 o'clock): top → 0.0, right (3 o'clock) → 0.25, bottom (6) →
    /// 0.5, left (9) → 0.75. Used by the Circular floating style.
    static func dialFraction(location: CGPoint, in size: CGSize) -> Double {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = location.x - center.x
        // SwiftUI's coordinate space has y increasing downward, so flip dy
        // to measure the angle in a conventional (y-up) sense before
        // reinterpreting it as clockwise-from-top below.
        let dy = location.y - center.y
        var angle = atan2(dx, -dy)
        let twoPi = 2 * Double.pi
        if angle < 0 { angle += CGFloat(twoPi) }
        return Double(angle) / twoPi
    }
}
