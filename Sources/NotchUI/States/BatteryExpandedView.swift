import SwiftUI

/// The expanded battery hub: a large charge ring, status line, and time detail.
struct BatteryExpandedView: View {
    let battery: BatteryInfo?
    let metrics: NotchMetrics

    var body: some View {
        HStack(spacing: 18) {
            ring
            VStack(alignment: .leading, spacing: 4) {
                Text("Battery")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Text("\(battery?.level ?? 0)%")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                Text(battery?.statusText ?? "No battery")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, metrics.notchHeight + 10)
        .padding(.horizontal, 30)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var level: Double { Double(battery?.level ?? 0) / 100 }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 7)
            Circle()
                .trim(from: 0, to: level)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: level)
            Image(systemName: (battery?.isCharging ?? false) ? "bolt.fill" : "battery.100")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ringColor)
        }
        .frame(width: 64, height: 64)
    }

    private var ringColor: Color {
        guard let battery else { return .white }
        if battery.isCharging || battery.isPluggedIn { return .green }
        if battery.level <= 20 { return .red }
        return .white
    }
}
