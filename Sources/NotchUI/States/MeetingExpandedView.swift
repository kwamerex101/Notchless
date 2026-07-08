import SwiftUI

/// The expanded meeting-capture panel: a record button when idle, a red consent
/// dot + elapsed timer + Stop while recording, transcribing/summarizing progress,
/// and a ready/failed result with a New/Dismiss button. Controls call the
/// injected `MeetingController` directly. Modeled on `TimerExpandedView`.
struct MeetingExpandedView: View {
    @ObservedObject var meeting: MeetingController
    let metrics: NotchMetrics

    var body: some View {
        HStack(spacing: 18) {
            badge
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            Spacer(minLength: 0)
        }
        .padding(.top, metrics.notchHeight + 10)
        .padding(.horizontal, 19)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // The left icon badge, mirroring the timer ring's footprint.
    private var badge: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.12))
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
        case .recording: return .red
        case .ready:     return .green
        case .failed:    return .orange
        default:         return .white
        }
    }

    @ViewBuilder private var content: some View {
        switch meeting.phase {
        case .idle:
            Text("Meeting")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Button {
                meeting.start()
            } label: {
                Label("Record meeting", systemImage: "record.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)

        case .recording:
            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text(timeString(meeting.elapsed))
                    .font(.system(size: 24, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            Button {
                meeting.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)

        case .transcribing:
            progress("Transcribing…")

        case .summarizing:
            progress("Summarizing…")

        case .ready:
            Text("Meeting ready")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            resetButton(title: "New")

        case let .failed(message):
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .lineLimit(2)
            resetButton(title: "Dismiss")
        }
    }

    private func progress(_ label: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(.white)
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private func resetButton(title: String) -> some View {
        Button {
            meeting.reset()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.14)))
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
