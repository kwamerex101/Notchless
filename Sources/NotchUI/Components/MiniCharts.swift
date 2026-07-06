import SwiftUI

/// A small filled pie chart used in the compact notch.
struct MiniPie: View {
    let slices: [(value: Double, color: Color)]

    var body: some View {
        Canvas { context, size in
            let total = slices.reduce(0) { $0 + $1.value }
            guard total > 0 else { return }
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            var start = Angle.degrees(-90)
            for slice in slices where slice.value > 0 {
                let sweep = Angle.degrees(slice.value / total * 360)
                let end = start + sweep
                var path = Path()
                path.move(to: center)
                path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
                path.closeSubpath()
                context.fill(path, with: .color(slice.color))
                start = end
            }
        }
    }
}

/// A simple line chart with a soft area fill, used in the expanded view.
struct MiniLineChart: View {
    let values: [Double]
    var color: Color = .green

    var body: some View {
        GeometryReader { geo in
            let maxValue = max(values.max() ?? 1, 1)
            let points = values.enumerated().map { index, value in
                CGPoint(
                    x: geo.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1)),
                    y: geo.size.height * (1 - CGFloat(value / maxValue))
                )
            }
            ZStack {
                // Area fill.
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: geo.size.height))
                    for point in points { path.addLine(to: point) }
                    path.addLine(to: CGPoint(x: points.last?.x ?? 0, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)],
                                     startPoint: .top, endPoint: .bottom))
                // Line.
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
