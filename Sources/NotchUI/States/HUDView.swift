import SwiftUI

/// Sound / Display HUD content: icon + label sliding out to the left, a white
/// progress bar on the right. Replaces the system OSD (see PLAN.md §1.1).
struct HUDView: View {
    let kind: HUDKind
    let metrics: NotchMetrics
    var options: HUDOptions = .default

    /// Level actually drawn in the bar — muted sound collapses to empty when
    /// `options.showMuteAsEmpty` is set (the icon already reads `speaker.slash.fill`).
    private var barLevel: Double {
        if case let .sound(_, muted) = kind, muted, options.showMuteAsEmpty {
            return 0
        }
        return kind.level
    }

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

            if case .sound = kind, options.showOutputDevice {
                Image(systemName: AudioOutputService.shared.currentOutputSymbol())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 16)
            }

            HUDBar(level: barLevel)
                .frame(width: 120, height: 6)

            if options.showPercentageLabel {
                Text("\(Int((kind.level * 100).rounded()))%")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize()
            }
        }
        // Clear the 18pt bottom corners (curve reaches ~27pt inward) and sit the
        // row in the region below the physical notch.
        .padding(.horizontal, 26)
        .padding(.bottom, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

/// Rounded-cap fill on a dim track; springs to each new level. `color`
/// defaults to white (the notch's look); floating HUD styles pass an
/// accent color when `hudUseAccentColor` is on.
struct HUDBar: View {
    let level: Double
    var color: Color = .white

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.22))
                Capsule().fill(color)
                    .frame(width: max(6, geo.size.width * CGFloat(min(1, max(0, level)))))
            }
        }
        .animation(NotchMotion.fill, value: level)
    }
}
