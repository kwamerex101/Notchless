import SwiftUI

/// Dictation content in the notch (ListenToMe). Recording shows a scrolling
/// waveform (sliver), settling into a panel with a live transcript and a
/// context/timer/cancel row. Transcribing/cleaning show a shimmer + transcript;
/// success/error collapse to a compact chip.
struct DictationView: View {
    let phase: DictationPhase
    let metrics: NotchMetrics
    @ObservedObject var audio: AudioLevelsModel
    var settled: Bool
    var startedAt: Date?
    var target: DictationTarget?
    var reduceMotion: Bool
    var onCancel: () -> Void

    var body: some View {
        content
            .padding(.top, metrics.notchHeight + 8)
            .padding(.horizontal, 22)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .recording:
            recordingBody
        case .transcribing, .cleaning:
            processingBody
        case let .success(text):
            resultChip(system: "checkmark.circle.fill", tint: .green, title: phase.label,
                       subtitle: text.isEmpty ? "Pasted" : text)
        case let .error(message):
            resultChip(system: "exclamationmark.triangle.fill", tint: .orange, title: phase.label,
                       subtitle: message)
        }
    }

    private var recordingBody: some View {
        VStack(spacing: 8) {
            ScrollingWaveform(level: audio.dictationLevel, isRecording: true, reduceMotion: reduceMotion)
            if settled {
                LiveTranscriptView(text: audio.dictationPartial, reduceMotion: reduceMotion)
                DictationControlRow(target: target, startedAt: startedAt, onCancel: onCancel)
                    .transition(.opacity)
            }
        }
    }

    private var processingBody: some View {
        VStack(spacing: 6) {
            ShimmerBar()
            LiveTranscriptView(text: audio.dictationPartial, reduceMotion: reduceMotion)
            Text(phase.label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func resultChip(system: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: system)
                .font(.system(size: 18))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A slim indeterminate shimmer used while transcribing/polishing.
private struct ShimmerBar: View {
    @State private var phase: CGFloat = -1
    var body: some View {
        GeometryReader { geo in
            Capsule().fill(.white.opacity(0.12))
                .overlay(
                    Capsule()
                        .fill(LinearGradient(colors: [.clear, .white.opacity(0.55), .clear],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * 0.4)
                        .offset(x: phase * geo.size.width)
                )
                .clipShape(Capsule())
        }
        .frame(height: 4)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                phase = 1
            }
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
