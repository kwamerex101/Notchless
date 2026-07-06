import SwiftUI

/// Dictation content in the notch (ListenToMe). A mic + live waveform while
/// recording, a spinner while transcribing/cleaning, and the final text on
/// success — styled to match the compact now-playing look.
struct DictationView: View {
    let phase: DictationPhase
    let metrics: NotchMetrics
    /// Live audio level 0…1 for the recording waveform.
    var level: CGFloat = 0.5

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
            RecordingWaveform(level: level)
                .frame(width: 46, height: 22)
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

/// A live, symmetric recording waveform that reacts to the audio level.
struct RecordingWaveform: View {
    var level: CGFloat
    var barCount: Int = 5

    @State private var seeds: [CGFloat]
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    init(level: CGFloat, barCount: Int = 5) {
        self.level = level
        self.barCount = barCount
        _seeds = State(initialValue: (0..<barCount).map { _ in CGFloat.random(in: 0.3...1) })
    }

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule()
                    .fill(Color(nsColor: .systemRed))
                    .frame(width: 3, height: max(4, 22 * seeds[i] * max(0.25, level)))
            }
        }
        .animation(.easeInOut(duration: 0.1), value: seeds)
        .onReceive(timer) { _ in
            seeds = seeds.map { _ in CGFloat.random(in: 0.3...1) }
        }
    }
}
