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

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? "Device"
        onConnect?(name)
        let key = device.addressString ?? name
        disconnectNotifications[key] = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:))
        )
    }

    @objc private func deviceDisconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? "Device"
        onDisconnect?(name)
        let key = device.addressString ?? name
        disconnectNotifications[key]?.unregister()
        disconnectNotifications[key] = nil
    }
}
