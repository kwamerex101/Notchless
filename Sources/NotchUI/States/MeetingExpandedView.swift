import SwiftUI

/// The expanded meeting-capture panel: a record button when idle, a pulsing
/// dot + elapsed timer + hold-to-stop while recording, transcribing/
/// summarizing progress, and a ready/failed result with a New/Dismiss
/// button. Controls call the injected `MeetingController` directly. Modeled
/// on `TimerExpandedView`. Flat-dark: monochrome white content, colour only
/// on the recording dot/square (docs/flat-dark-spec.md §3).
struct MeetingExpandedView: View {
    @ObservedObject var meeting: MeetingController
    let metrics: NotchMetrics

    var body: some View {
        Group {
            if case .recording = meeting.phase {
                recordingRow
            } else {
                HStack(spacing: 18) {
                    badge
                    VStack(alignment: .leading, spacing: 8) { content }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.top, 42)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // The exact "Expanded · Meeting" layout — docs/flat-dark-spec.md §3.
    private var recordingRow: some View {
        HStack(spacing: 12) {
            PulsingDot(color: NotchTheme.recording, size: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text("Recording meeting")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NotchTheme.textPrimary)
                Text("Transcribing on-device")
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTheme.textSecondary)
            }
            Spacer(minLength: 12)
            Text(timeString(meeting.elapsed))
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(NotchTheme.textPrimary)
            HoldToStopButton { meeting.stop() }
        }
    }

    // The left icon badge, mirroring the timer ring's footprint. Used by
    // every phase except `.recording`, which has its own row layout.
    private var badge: some View {
        ZStack {
            Circle().fill(NotchTheme.chip)
            Image(systemName: badgeSymbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(badgeTint)
        }
        .frame(width: 58, height: 58)
    }

    private var badgeSymbol: String {
        switch meeting.phase {
        case .idle:         return "record.circle"
        case .recording:    return "waveform"
        case .transcribing, .summarizing: return "waveform"
        case .ready:        return "checkmark.circle.fill"
        case .failed:       return "exclamationmark.triangle.fill"
        }
    }

    private var badgeTint: Color {
        switch meeting.phase {
        case .recording: return NotchTheme.recording
        case .ready:     return NotchTheme.positive
        case .failed:    return NotchTheme.warning
        default:         return NotchTheme.textPrimary
        }
    }

    @ViewBuilder private var content: some View {
        switch meeting.phase {
        case .idle:
            Text("Meeting")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchTheme.textSecondary)
            Button {
                meeting.start()
            } label: {
                Label("Record meeting", systemImage: "record.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NotchTheme.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(NotchTheme.chip))
            }
            .buttonStyle(.plain)

        case .recording:
            // Unreachable — `.recording` is routed to `recordingRow` above.
            EmptyView()

        case .transcribing:
            progress("Transcribing…")

        case .summarizing:
            progress("Summarizing…")

        case let .ready(id):
            let record = meeting.records.first(where: { $0.id == id })
            if record?.summaryFailed == true {
                Text("Transcript ready · summary failed")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NotchTheme.warning)
                if let reason = meeting.summaryError {
                    Text(reason)
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTheme.textSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Button {
                        meeting.rerunSummary(id: id)
                    } label: {
                        Text("Retry summary")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NotchTheme.textPrimary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(NotchTheme.chip))
                    }
                    .buttonStyle(.plain)
                    resetButton(title: "New")
                }
            } else {
                Text("Meeting ready")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NotchTheme.textPrimary)
                resetButton(title: "New")
            }

        case let .failed(message):
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(NotchTheme.warning)
                .lineLimit(2)
            resetButton(title: "Dismiss")
        }
    }

    private func progress(_ label: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(NotchTheme.textPrimary)
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchTheme.textPrimary)
        }
    }

    private func resetButton(title: String) -> some View {
        Button {
            meeting.reset()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchTheme.textPrimary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(NotchTheme.chip))
        }
        .buttonStyle(.plain)
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }
}

/// A 32x32 circular stop button that requires a 600ms hold before it fires,
/// filling a ring around itself while held; releasing early cancels without
/// calling `onStop` — docs/flat-dark-spec.md §4 (Meeting stop).
private struct HoldToStopButton: View {
    var onStop: () -> Void

    @State private var progress: CGFloat = 0
    @State private var isHolding = false

    private let holdDuration: TimeInterval = 0.6

    var body: some View {
        ZStack {
            Circle().fill(NotchTheme.chip)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(NotchTheme.recording, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(NotchTheme.recording)
                .frame(width: 10, height: 10)
        }
        .frame(width: 32, height: 32)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in beginHold() }
                .onEnded { _ in cancelHold() }
        )
    }

    private func beginHold() {
        guard !isHolding else { return }
        isHolding = true
        withAnimation(.linear(duration: holdDuration)) {
            progress = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration) {
            guard isHolding else { return }
            isHolding = false
            progress = 0
            onStop()
        }
    }

    private func cancelHold() {
        guard isHolding else { return }
        isHolding = false
        withAnimation(.easeOut(duration: 0.15)) { progress = 0 }
    }
}
