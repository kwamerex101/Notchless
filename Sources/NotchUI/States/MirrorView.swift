import SwiftUI
import AVFoundation

/// Camera-mirror content: a live, horizontally-mirrored front-camera preview in
/// the notch so you can check yourself before a call. The session runs only
/// while this view is on screen.
struct MirrorView: View {
    let metrics: NotchMetrics
    var onClose: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: metrics.notchHeight)
            CameraPreview(session: CameraSession.shared.session)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(radius: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { CameraSession.shared.start() }
        .onDisappear { CameraSession.shared.stop() }
    }
}

/// Wraps an AVCaptureVideoPreviewLayer, mirrored so it reads like a mirror.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        if let connection = preview.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        view.layer = preview
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
