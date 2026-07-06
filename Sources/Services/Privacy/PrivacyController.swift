import Foundation
import CoreAudio
import CoreMediaIO

/// Detects camera / microphone use via public "is running somewhere" device
/// properties and publishes it to `model.privacy`, so the notch can show a
/// privacy dot like macOS's own indicator.
@MainActor
final class PrivacyController {
    private let model: NotchViewModel
    private var timer: Timer?

    init(model: NotchViewModel) {
        self.model = model
    }

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        guard model.settings.privacyIndicatorEnabled else {
            if model.privacy != nil { model.privacy = nil }
            return
        }
        let status = PrivacyStatus(cameraActive: Self.cameraInUse(), micActive: Self.micInUse())
        model.privacy = status.isActive ? status : nil
    }

    // MARK: - Microphone (CoreAudio)

    private static func micInUse() -> Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var inputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &inputAddr, 0, nil, &size, &device) == noErr, device != 0 else { return false }

        var running: UInt32 = 0
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        var runningAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(device, &runningAddr, 0, nil, &runningSize, &running) == noErr else { return false }
        return running != 0
    }

    // MARK: - Camera (CoreMediaIO)

    private static func cameraInUse() -> Bool {
        var devicesAddr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))

        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject),
                                            &devicesAddr, 0, nil, &dataSize) == noErr, dataSize > 0 else { return false }
        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject),
                                        &devicesAddr, 0, nil, dataSize, &used, &devices) == noErr else { return false }

        var runningAddr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        for device in devices where device != 0 {
            var running: UInt32 = 0
            var runningUsed: UInt32 = 0
            let status = CMIOObjectGetPropertyData(device, &runningAddr, 0, nil,
                                                   UInt32(MemoryLayout<UInt32>.size), &runningUsed, &running)
            if status == noErr, running != 0 { return true }
        }
        return false
    }
}
