import SwiftUI

/// The expanded privacy panel: shows which sensors (camera / microphone) are
/// currently active, with a coloured dot each — mirroring macOS's indicator.
struct PrivacyExpandedView: View {
    let privacy: PrivacyStatus?
    let metrics: NotchMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("In use")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            if privacy?.cameraActive ?? false {
                row(dot: .green, icon: "camera.fill", label: "Camera")
            }
            if privacy?.micActive ?? false {
                row(dot: .orange, icon: "mic.fill", label: "Microphone")
            }
            if !(privacy?.isActive ?? false) {
                Text("Camera and microphone are off.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.top, metrics.notchHeight + 10)
        .padding(.horizontal, 19)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(dot: Color, icon: String, label: String) -> some View {
        HStack(spacing: 10) {
            Circle().fill(dot).frame(width: 9, height: 9)
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20)
            Text("\(label) in use")
                .font(.system(size: 13))
                .foregroundStyle(.white)
            Spacer()
        }
    }
}
