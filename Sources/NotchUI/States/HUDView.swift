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

    /// Glyph footprint per kind — spec §3 "HUD" table (16x14 speaker, 15x15 sun).
    private var glyphSize: CGSize {
        switch kind {
        case .sound: return CGSize(width: 16, height: 14)
        case .display: return CGSize(width: 15, height: 15)
        }
    }

    /// Spec §3 calls the sound HUD's label `Volume` (the brightness one is
    /// already `Brightness`); `HUDKind.label` says `Sound`, so override it
    /// here rather than changing the shared enum.
    private var label: String {
        switch kind {
        case .sound: return "Volume"
        case .display: return kind.label
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchTheme.textPrimary)
                .frame(width: glyphSize.width, height: glyphSize.height)
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(NotchTheme.textPrimary)
                .fixedSize()

            Spacer(minLength: 12)

            // The output-device glyph is settings-gated but doesn't belong in
            // this layout (spec §3: exactly one leading glyph before the
            // bar); the `options.showOutputDevice` setting stays wired up
            // for whichever surface does render it.

            HUDBar(level: barLevel, color: NotchTheme.fill, trackColor: NotchTheme.track)
                .frame(width: 120, height: 6)
                .padding(.bottom, 3)

            if options.showPercentageLabel {
                Text("\(Int((kind.level * 100).rounded()))%")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(NotchTheme.textPrimary)
                    .fixedSize()
            }
        }
        // Spec §3 "HUD": 490x68, radius 18, content bottom-aligned, padding 0/26/15.
        .padding(.horizontal, 26)
        .padding(.bottom, 15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

/// Rounded-cap fill on a dim track; springs to each new level. `color`
/// defaults to white (the notch's look); floating HUD styles pass an
/// accent color when `hudUseAccentColor` is on.
struct HUDBar: View {
    let level: Double
    var color: Color = .white
    /// Unfilled track colour. `nil` (the default, used by the other HUD
    /// styles) keeps the original dim-of-`color` look; the flat-dark notch
    /// HUD passes the fixed `NotchTheme.track` token explicitly.
    var trackColor: Color?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(trackColor ?? color.opacity(0.22))
                Capsule().fill(color)
                    .frame(width: max(6, geo.size.width * CGFloat(min(1, max(0, level)))))
            }
        }
        .animation(NotchMotion.fill, value: level)
    }
}
