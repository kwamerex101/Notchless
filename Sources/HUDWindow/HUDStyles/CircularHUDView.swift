import SwiftUI

/// A circular dial: a track ring plus a trimmed arc (or a ring of dots when
/// `indicator == .dot`, a continuous stroke when `.line`), with the icon
/// and/or numeric percentage centered.
/// on-device: tune visuals
struct CircularHUDView: View {
    let kind: HUDKind
    let options: HUDOptions
    let accent: Color?
    let indicator: HUDIndicator

    static let estimatedSize = CGSize(width: 120, height: 120)

    /// Pure clamp of a raw level into the `0...1` trim range a `Circle`'s
    /// `trim(to:)` (or a dot-ring fill count) can consume directly.
    static func trimEnd(for level: Double) -> Double {
        min(1, max(0, level))
    }

    private var barLevel: Double {
        if case let .sound(_, muted) = kind, muted, options.showMuteAsEmpty {
            return 0
        }
        return kind.level
    }

    private var fillColor: Color { accent ?? .white }

    private static let dotCount = 24

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 8)

            ring

            VStack(spacing: 2) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                if options.showPercentageLabel {
                    Text("\(Int((kind.level * 100).rounded()))%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(14)
        .background(Circle().fill(.black))
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var ring: some View {
        switch indicator {
        case .line:
            Circle()
                .trim(from: 0, to: Self.trimEnd(for: barLevel))
                .stroke(fillColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(NotchMotion.fill, value: barLevel)
        case .dot:
            let litCount = Int((Self.trimEnd(for: barLevel) * Double(Self.dotCount)).rounded())
            ForEach(0..<Self.dotCount, id: \.self) { i in
                Circle()
                    .fill(i < litCount ? fillColor : Color.white.opacity(0.22))
                    .frame(width: 4, height: 4)
                    .offset(y: -46)
                    .rotationEffect(.degrees(Double(i) / Double(Self.dotCount) * 360))
            }
            .animation(NotchMotion.fill, value: barLevel)
        }
    }
}
