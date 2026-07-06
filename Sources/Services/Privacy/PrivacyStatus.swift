import Foundation

/// Whether the camera and/or microphone are currently in use by any app.
struct PrivacyStatus: Equatable {
    var cameraActive: Bool
    var micActive: Bool

    var isActive: Bool { cameraActive || micActive }

    var label: String {
        switch (cameraActive, micActive) {
        case (true, true): return "Camera & Mic"
        case (true, false): return "Camera"
        case (false, true): return "Microphone"
        default: return ""
        }
    }
}
