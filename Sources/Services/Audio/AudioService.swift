import CoreAudio
import Foundation

/// Watches the default output device's volume and mute, reporting changes so
/// the notch can show the Sound HUD. Pure public CoreAudio — no special
/// permission required.
@MainActor
final class AudioService {
    var onChange: ((_ level: Double, _ muted: Bool) -> Void)?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private let queue = DispatchQueue(label: "audio.service")
    private var volumeBlock: AudioObjectPropertyListenerBlock?
    private var muteBlock: AudioObjectPropertyListenerBlock?

    func start() {
        device = Self.defaultOutputDevice()
        installListeners()
        observeDefaultDeviceChanges()
    }

    private static func defaultOutputDevice() -> AudioObjectID {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    private func installListeners() {
        guard device != kAudioObjectUnknown else { return }

        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let volBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.emit()
        }
        volumeBlock = volBlock
        AudioObjectAddPropertyListenerBlock(device, &volAddr, queue, volBlock)

        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let muteBlk: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.emit()
        }
        muteBlock = muteBlk
        AudioObjectAddPropertyListenerBlock(device, &muteAddr, queue, muteBlk)
    }

    private func observeDefaultDeviceChanges() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, queue
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.device = AudioService.defaultOutputDevice()
                self?.installListeners()
            }
        }
    }

    private func emit() {
        let level = currentVolume()
        let muted = currentMute()
        Task { @MainActor in self.onChange?(level, muted) }
    }

    private func currentVolume() -> Double {
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        if status == noErr { return Double(value) }

        // Fall back to averaging the two front channels.
        var total: Float32 = 0
        var count: Float32 = 0
        for channel: UInt32 in [1, 2] {
            var chAddr = address
            chAddr.mElement = channel
            var v: Float32 = 0
            var s = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &chAddr, 0, nil, &s, &v) == noErr {
                total += v; count += 1
            }
        }
        return count > 0 ? Double(total / count) : 0
    }

    private func currentMute() -> Bool {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr && value != 0
    }
}
