import AVFoundation

/// Owns the AVCaptureSession for the camera mirror. Started only while the
/// mirror is visible, so the camera light isn't on otherwise.
@MainActor
final class CameraSession {
    static let shared = CameraSession()

    let session = AVCaptureSession()
    private var configured = false
    private let queue = DispatchQueue(label: "notchless.camera")

    func start() {
        requestAccess { [weak self] granted in
            guard granted, let self else { return }
            self.configureIfNeeded()
            self.queue.async {
                if !self.session.isRunning { self.session.startRunning() }
            }
        }
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        configured = true
        session.beginConfiguration()
        session.sessionPreset = .high
        if let device = AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        session.commitConfiguration()
    }

    private func requestAccess(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }
}
