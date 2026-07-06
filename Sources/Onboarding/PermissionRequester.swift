import EventKit
import CoreLocation
import CoreBluetooth
import ApplicationServices
import AVFoundation
import AppKit

/// Triggers the real system permission prompts, one per onboarding step.
@MainActor
final class PermissionRequester: NSObject {
    static let shared = PermissionRequester()

    private var locationManager: CLLocationManager?
    private var central: CBCentralManager?

    func request(_ kind: PermissionKind) {
        switch kind {
        case .calendar:
            EKEventStore().requestFullAccessToEvents { _, _ in }
        case .location:
            let manager = CLLocationManager()
            manager.requestWhenInUseAuthorization()
            locationManager = manager
        case .bluetooth:
            // Instantiating a central manager surfaces the Bluetooth prompt.
            central = CBCentralManager(delegate: nil, queue: nil)
        case .accessibility:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        case .camera:
            AVCaptureDevice.requestAccess(for: .video) { _ in }
        }
    }
}
