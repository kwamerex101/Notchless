import SwiftUI

/// Sound / Display HUD content: icon + label sliding out to the left, a white
/// progress bar on the right. Replaces the system OSD (see PLAN.md §1.1).
struct HUDView: View {
    let kind: HUDKind
    let metrics: NotchMetrics

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 18)
            Text(kind.label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize()

            Spacer(minLength: 12)

            HUDBar(level: kind.level)
                .frame(width: 120, height: 6)
        }
        // Clear the 18pt bottom corners (curve reaches ~27pt inward) and sit the
        // row in the region below the physical notch.
        .padding(.horizontal, 26)
        .padding(.bottom, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

/// White rounded-cap fill on a dim track; springs to each new level.
struct HUDBar: View {
    let level: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22))
                Capsule().fill(Color.white)
                    .frame(width: max(6, geo.size.width * CGFloat(min(1, max(0, level)))))
            }
        }
        .animation(NotchMotion.fill, value: level)
    }
}
