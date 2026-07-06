import SwiftUI

/// The notch silhouette: flush square top corners with small outward-flaring
/// concave fillets where it meets the screen edge, and rounded convex bottom
/// corners. Both radii are animatable so the shape can spring-morph between
/// states.
struct NotchShape: Shape {
    /// Radius of the concave fillet at the top edges (the flare into the screen).
    var topCornerRadius: CGFloat
    /// Radius of the convex rounding at the bottom corners.
    var bottomCornerRadius: CGFloat

    init(topCornerRadius: CGFloat = 7, bottomCornerRadius: CGFloat = 10) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tr = max(0, min(topCornerRadius, rect.height / 2))
        let br = max(0, min(bottomCornerRadius, min(rect.width / 2 - tr, rect.height - tr)))

        // Start at the very top-left, flush with the screen edge.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Concave fillet curving down-inward into the body.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tr, y: rect.minY + tr),
            control: CGPoint(x: rect.minX + tr, y: rect.minY)
        )
        // Left side down.
        path.addLine(to: CGPoint(x: rect.minX + tr, y: rect.maxY - br))
        // Bottom-left convex corner.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + tr + br, y: rect.maxY),
            control: CGPoint(x: rect.minX + tr, y: rect.maxY)
        )
        // Bottom edge.
        path.addLine(to: CGPoint(x: rect.maxX - tr - br, y: rect.maxY))
        // Bottom-right convex corner.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - tr, y: rect.maxY - br),
            control: CGPoint(x: rect.maxX - tr, y: rect.maxY)
        )
        // Right side up.
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY + tr))
        // Concave fillet back out to the top edge.
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - tr, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
