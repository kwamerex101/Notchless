import SwiftUI

/// Dictation content in the notch (ListenToMe). A mic + live waveform while
/// recording, a spinner while transcribing/cleaning, and the final text on
/// success — styled to match the compact now-playing look.
struct DictationView: View {
    let phase: DictationPhase
    let metrics: NotchMetrics
    /// Live audio level 0…1 for the recording waveform.
    var level: CGFloat = 0.5
    /// Live frequency-band levels (low→high) driving the waveform.
    var spectrum: [CGFloat] = []

    var body: some View {
        HStack(spacing: 12) {
            icon
            content
            Spacer(minLength: 0)
            trailing
        }
        .padding(.top, metrics.notchHeight + 6)
        .padding(.horizontal, 26)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var icon: some View {
        let tint: Color = {
            switch phase {
            case .recording: return Color(nsColor: .systemRed)
            case .success: return .green
            case .error: return .orange
            default: return .teal
            }
        }()
        Image(systemName: phase.systemImage)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(Circle().fill(tint.gradient))
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(phase.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            switch phase {
            case let .success(text):
                Text(text.isEmpty ? "Pasted" : text)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            case let .error(message):
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        switch phase {
        case .recording:
            RecordingWaveform(spectrum: spectrum)
                .frame(width: 96, height: 26)
        case .transcribing, .cleaning:
            ProgressView()
                .controlSize(.small)
                .tint(.white)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.green)
        case .error:
            EmptyView()
        }
    }
}

/// Shown when the dictation idle activity is hovered — a calm affordance
/// telling the user how to start.
struct DictationHintView: View {
    let metrics: NotchMetrics
    @ObservedObject private var settings = DictationSettings.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mic.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.teal.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text("Dictate anywhere")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Hold \(settings.hotkey.title), then speak")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, metrics.notchHeight + 6)
        .padding(.horizontal, 26)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// A symmetric recording waveform driven by the live audio spectrum: it mirrors
/// out from the center bar, tall bars tracking whichever tones are present. When
/// nothing is being said it settles into a slow heartbeat pulse.
struct RecordingWaveform: View {
    var spectrum: [CGFloat]
    var barCount: Int = 11

    private let maxHeight: CGFloat = 26
    private let minHeight: CGFloat = 3
    /// Below this the input counts as silence → heartbeat.
    private let speakingThreshold: CGFloat = 0.06

    var body: some View {
        // TimelineView drives the continuous heartbeat; when speech arrives the
        // spectrum takes over.
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(Color(nsColor: .systemRed))
                        .frame(width: 3, height: height(at: i, time: t))
                }
            }
            .animation(.spring(response: 0.16, dampingFraction: 0.6), value: spectrum)
        }
    }

    private var center: Int { (barCount - 1) / 2 }

    private var energy: CGFloat { spectrum.max() ?? 0 }

    private func height(at index: Int, time: TimeInterval) -> CGFloat {
        let distance = abs(index - center)   // 0 at center, grows outward

        if energy > speakingThreshold {
            // Symmetric: center = lowest band, mirroring out to higher tones.
            let band = spectrum.isEmpty ? 0 : spectrum[min(distance, spectrum.count - 1)]
            return minHeight + (maxHeight - minHeight) * band
        }

        // Heartbeat: a soft double-thump that ripples out from the center.
        let cycle = 1.15
        let phase = time.truncatingRemainder(dividingBy: cycle) / cycle
        let beat = thump(phase, at: 0.0) + 0.6 * thump(phase, at: 0.16)
        let falloff = 1 - (CGFloat(distance) / CGFloat(center + 1)) * 0.65
        let pulse = (0.10 + 0.22 * CGFloat(beat)) * falloff
        return minHeight + (maxHeight - minHeight) * pulse
    }

    /// A narrow gaussian "beat" centered at `at` within the 0…1 cycle.
    private func thump(_ phase: Double, at: Double) -> Double {
        let d = phase - at
        return exp(-(d * d) / (2 * 0.0015))
    }
}
