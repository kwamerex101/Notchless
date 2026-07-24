import SwiftUI

/// The expanded timer panel: a countdown ring with start/pause/reset, or preset
/// buttons when idle. Controls call `TimerController.shared` directly.
struct TimerExpandedView: View {
    let timer: NotchTimerInfo?
    let metrics: NotchMetrics

    private let presets: [(String, Int)] = [("1m", 60), ("5m", 300), ("10m", 600), ("25m", 1500)]

    var body: some View {
        HStack(spacing: 18) {
            ring
            VStack(alignment: .leading, spacing: 8) {
                if let timer, timer.isActive {
                    Text(timer.label)
                        .font(.system(size: 24, weight: .bold).monospacedDigit())
                        .foregroundStyle(NotchTheme.textPrimary)
                    controls(for: timer)
                } else {
                    Text("Timer")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NotchTheme.textSecondary)
                    presetRow
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, metrics.notchHeight + 10)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Colour only where it means something: white while counting down,
    /// `warning` once the timer has finished.
    private var ringColor: Color {
        (timer?.isFinished ?? false) ? NotchTheme.warning : NotchTheme.fill
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(NotchTheme.ringTrack, lineWidth: 6)
            Circle()
                .trim(from: 0, to: timer?.progress ?? 0)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: timer?.progress ?? 0)
            Image(systemName: "timer")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(NotchTheme.textPrimary)
        }
        .frame(width: 58, height: 58)
    }

    private var presetRow: some View {
        HStack(spacing: 6) {
            ForEach(presets, id: \.0) { preset in
                Button(preset.0) { TimerController.shared?.begin(seconds: preset.1) }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NotchTheme.textPrimary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(NotchTheme.chip))
            }
        }
    }

    private func controls(for timer: NotchTimerInfo) -> some View {
        HStack(spacing: 10) {
            if timer.isRunning {
                iconButton("pause.fill") { TimerController.shared?.pause() }
            } else if !timer.isFinished {
                iconButton("play.fill") { TimerController.shared?.resume() }
            }
            iconButton("arrow.counterclockwise") { TimerController.shared?.reset() }
            iconButton("xmark") { TimerController.shared?.cancel() }
        }
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchTheme.textPrimary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(NotchTheme.chip))
        }
        .buttonStyle(.plain)
    }
}
