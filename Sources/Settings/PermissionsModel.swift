import SwiftUI
import AVFoundation
import Speech
import EventKit
import CoreLocation
import CoreBluetooth
import ApplicationServices

/// A single macOS permission Notchless can use, with the feature it powers.
enum AppPermission: String, CaseIterable, Identifiable {
    case accessibility
    case microphone
    case speechRecognition
    case camera
    case calendar
    case location
    case bluetooth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .microphone: return "Microphone"
        case .speechRecognition: return "Speech Recognition"
        case .camera: return "Camera"
        case .calendar: return "Calendar"
        case .location: return "Location"
        case .bluetooth: return "Bluetooth"
        }
    }

    var purpose: String {
        switch self {
        case .accessibility: return "Hold-to-talk hotkey and pasting dictated text"
        case .microphone: return "Recording your voice for dictation"
        case .speechRecognition: return "On-device transcription with Apple Speech"
        case .camera: return "The camera mirror in the notch"
        case .calendar: return "Showing upcoming events"
        case .location: return "Weather and location-based activities"
        case .bluetooth: return "Nearby-device battery in the notch"
        }
    }

    var systemImage: String {
        switch self {
        case .accessibility: return "accessibility"
        case .microphone: return "mic.fill"
        case .speechRecognition: return "waveform"
        case .camera: return "camera.fill"
        case .calendar: return "calendar"
        case .location: return "location.fill"
        case .bluetooth: return "dot.radiowaves.right"
        }
    }

    /// Deep link to the matching System Settings privacy pane.
    var settingsURL: URL? {
        let anchor: String
        switch self {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .microphone: anchor = "Privacy_Microphone"
        case .speechRecognition: anchor = "Privacy_SpeechRecognition"
        case .camera: anchor = "Privacy_Camera"
        case .calendar: anchor = "Privacy_Calendars"
        case .location: anchor = "Privacy_LocationServices"
        case .bluetooth: anchor = "Privacy_Bluetooth"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }
}

enum PermissionState {
    case granted
    case denied
    case notDetermined

    var label: String {
        switch self {
        case .granted: return "Enabled"
        case .denied: return "Disabled"
        case .notDetermined: return "Not set"
        }
    }

    var color: Color {
        switch self {
        case .granted: return .green
        case .denied: return .red
        case .notDetermined: return .orange
        }
    }
}

/// Reads live authorization status for each permission and drives the
/// request / open-in-System-Settings actions.
@MainActor
final class PermissionsModel: ObservableObject {
    @Published private(set) var states: [AppPermission: PermissionState] = [:]

    private let locationManager = CLLocationManager()
    private var pollTimer: Timer?

    func refresh() {
        var next: [AppPermission: PermissionState] = [:]
        for permission in AppPermission.allCases {
            next[permission] = state(for: permission)
        }
        if next != states { states = next }
    }

    /// Permissions change out-of-band (the system prompt, or the user toggling
    /// them in System Settings), so poll while the pane is on screen.
    func startAutoRefresh() {
        refresh()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopAutoRefresh() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Not-set permissions trigger the system prompt; already-decided ones open
    /// System Settings (macOS won't let an app flip its own grant).
    ///
    /// Accessibility is special: `AXIsProcessTrusted()` never reports
    /// "not determined", so we always fire the prompt — that's also what
    /// registers the app in the Accessibility list so a toggle even appears —
    /// and then open Settings so the user can flip it on.
    func act(on permission: AppPermission) {
        if permission == .accessibility {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
            if let url = permission.settingsURL {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSWorkspace.shared.open(url) }
            }
            return
        }
        if states[permission] == .notDetermined {
            request(permission)
            // Re-read shortly after the prompt is answered.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.refresh() }
        } else if let url = permission.settingsURL {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Status

    private func state(for permission: AppPermission) -> PermissionState {
        switch permission {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        case .microphone:
            return map(AVCaptureDevice.authorizationStatus(for: .audio))
        case .camera:
            return map(AVCaptureDevice.authorizationStatus(for: .video))
        case .speechRecognition:
            return mapSpeech(SFSpeechRecognizer.authorizationStatus())
        case .calendar:
            return mapCalendar(EKEventStore.authorizationStatus(for: .event))
        case .location:
            return mapLocation(locationManager.authorizationStatus)
        case .bluetooth:
            return mapBluetooth(CBManager.authorization)
        }
    }

    private func map(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    private func mapSpeech(_ status: SFSpeechRecognizerAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    private func mapCalendar(_ status: EKAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized, .fullAccess, .writeOnly: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    private func mapLocation(_ status: CLAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorizedAlways, .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    private func mapBluetooth(_ status: CBManagerAuthorization) -> PermissionState {
        switch status {
        case .allowedAlways: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    // MARK: - Requests

    private func request(_ permission: AppPermission) {
        switch permission {
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        case .camera:
            AVCaptureDevice.requestAccess(for: .video) { _ in }
        case .speechRecognition:
            SFSpeechRecognizer.requestAuthorization { _ in }
        case .calendar:
            EKEventStore().requestFullAccessToEvents { _, _ in }
        case .location:
            locationManager.requestWhenInUseAuthorization()
        case .bluetooth:
            // Reading authorization is enough to surface the prompt lazily; a
            // central manager instantiation would also do it.
            _ = CBCentralManager()
        }
    }
}
