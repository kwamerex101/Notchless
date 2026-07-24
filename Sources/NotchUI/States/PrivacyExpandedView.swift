import SwiftUI

/// The expanded privacy panel: shows which sensors (camera / microphone) are
/// currently active, with a pulsing dot each — mirroring macOS's indicator.
/// Flat-dark: monochrome text, colour only on the sensor dots
/// (docs/flat-dark-spec.md §3).
struct PrivacyExpandedView: View {
    let privacy: PrivacyStatus?
    let metrics: NotchMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if privacy?.cameraActive ?? false {
                row(dot: NotchTheme.positive, label: "Camera in use", phaseOffset: 0)
            }
            if privacy?.micActive ?? false {
                row(dot: NotchTheme.warning, label: "Microphone in use", phaseOffset: 0.8)
            }
            if !(privacy?.isActive ?? false) {
                Text("Camera and microphone are off.")
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTheme.textSecondary)
            }
        }
        .padding(.top, 42)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(dot: Color, label: String, phaseOffset: TimeInterval) -> some View {
        HStack(spacing: 10) {
            PulsingDot(color: dot, size: 8, phaseOffset: phaseOffset)
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NotchTheme.textPrimary)
            Spacer()
        }
    }
}
