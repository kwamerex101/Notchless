import IOBluetooth
import Foundation

/// Reports Bluetooth device connects/disconnects (AirPods, headphones, etc.)
/// for the Connectivity notification. See PLAN.md Phase 8.
@MainActor
final class BluetoothService: NSObject {
    var onConnect: ((_ name: String) -> Void)?
    var onDisconnect: ((_ name: String) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]

    func start() {
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    // These are `nonisolated` because IOBluetooth delivers the notification on
    // whatever thread it likes — the legacy connect registration fires on the
    // main run loop, but the CoreBluetooth coordinator also routes the same
    // event on its own background queue. Calling the @MainActor body directly
    // off-thread made `model.show()` publish from two threads at once, which
    // deadlocked Combine's ObservableObjectPublisher at launch. So we hop to
    // main ourselves and do all state/publish work there, serially.
    @objc private nonisolated func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? "Device"
        let key = device.addressString ?? name
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.onConnect?(name)
                self.disconnectNotifications[key] = device.register(
                    forDisconnectNotification: self,
                    selector: #selector(self.deviceDisconnected(_:device:))
                )
            }
        }
    }

    @objc private nonisolated func deviceDisconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? "Device"
        let key = device.addressString ?? name
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.onDisconnect?(name)
                self.disconnectNotifications[key]?.unregister()
                self.disconnectNotifications[key] = nil
            }
        }
    }
}
