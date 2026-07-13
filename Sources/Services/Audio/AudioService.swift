import CoreAudio
import Foundation

/// Origin of a reported volume/mute change.
/// - `initial`: the first emission after `start()` (a snapshot, not a change).
/// - `selfWrite`: matches a recent `setVolume` call made by this app.
/// - `external`: anything else (hardware keys, another app, System Settings).
enum VolumeChangeOrigin {
    case initial
    case selfWrite
    case external
}

/// Watches the default output device's volume and mute, reporting changes so
/// the notch can show the Sound HUD. Pure public CoreAudio — no special
/// permission required.
@MainActor
final class AudioService {
    var onChange: ((_ level: Double, _ muted: Bool, _ origin: VolumeChangeOrigin) -> Void)?

    /// Fired once after `start()` and again whenever the default device
    /// changes, reporting whether the (new) device exposes any volume
    /// property we can observe. `false` means the HUD/OSD suppression
    /// should back off since we'd be flying blind.
    var onDeviceChange: ((_ supportsVolume: Bool) -> Void)?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private let queue = DispatchQueue(label: "audio.service")
    private var volumeBlock: AudioObjectPropertyListenerBlock?
    private var muteBlock: AudioObjectPropertyListenerBlock?

    private var hasEmitted = false
    /// The last app-initiated volume write, used to classify the next
    /// listener-driven emission as `.selfWrite` vs `.external`.
    private var pendingSelfWrite: (target: Double, at: Date)?

    /// What's currently installed on `installedDevice`, so `removeListeners()`
    /// can tear it down before re-installing on a new default device.
    private var installedDevice = AudioObjectID(kAudioObjectUnknown)
    private var installedVolumeAddrs: [AudioObjectPropertyAddress] = []

    func start() {
        device = Self.defaultOutputDevice()
        hasEmitted = false
        installListeners()
        onDeviceChange?(currentDeviceSupportsVolume())
        observeDefaultDeviceChanges()
    }

    /// Requests an app-initiated volume change. Clamped to `0...1`. Stamps
    /// `pendingSelfWrite` before writing so the resulting CoreAudio listener
    /// callback is classified `.selfWrite` rather than `.external`. Does not
    /// emit directly — the listener does that once CoreAudio confirms it.
    func setVolume(_ level: Double) {
        let clamped = min(max(level, 0), 1)
        pendingSelfWrite = (clamped, Date())
        guard device != kAudioObjectUnknown else { return }

        var value = Float32(clamped)
        let size = UInt32(MemoryLayout<Float32>.size)
        var mainAddr = Self.mainVolumeAddress()
        if AudioObjectHasProperty(device, &mainAddr) {
            AudioObjectSetPropertyData(device, &mainAddr, 0, nil, size, &value)
        } else {
            for channel: UInt32 in [1, 2] {
                var chAddr = Self.mainVolumeAddress()
                chAddr.mElement = channel
                if AudioObjectHasProperty(device, &chAddr) {
                    AudioObjectSetPropertyData(device, &chAddr, 0, nil, size, &value)
                }
            }
        }
    }

    /// Pure classifier — the app is "hearing" `level` from a listener
    /// callback and asking whether it looks like an echo of `pending` (a
    /// recent `setVolume` write) or an external change. `<=` at both
    /// boundaries: exactly-at-window and exactly-at-tolerance still count
    /// as self-write.
    nonisolated static func classifyOrigin(
        level: Double, now: Date, pending: (target: Double, at: Date)?,
        window: TimeInterval = 0.15, tolerance: Double = 0.02
    ) -> VolumeChangeOrigin {
        guard let pending else { return .external }
        guard now.timeIntervalSince(pending.at) <= window else { return .external }
        guard abs(level - pending.target) <= tolerance else { return .external }
        return .selfWrite
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

    private static func mainVolumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func currentDeviceSupportsVolume() -> Bool {
        guard device != kAudioObjectUnknown else { return false }
        var mainAddr = Self.mainVolumeAddress()
        if AudioObjectHasProperty(device, &mainAddr) { return true }
        for channel: UInt32 in [1, 2] {
            var chAddr = Self.mainVolumeAddress()
            chAddr.mElement = channel
            if AudioObjectHasProperty(device, &chAddr) { return true }
        }
        return false
    }

    private func installListeners() {
        removeListeners()
        guard device != kAudioObjectUnknown else { return }

        let volBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.emit() }
        }
        volumeBlock = volBlock

        var mainAddr = Self.mainVolumeAddress()
        var volumeAddrs: [AudioObjectPropertyAddress] = []
        if AudioObjectHasProperty(device, &mainAddr) {
            var addr = mainAddr
            AudioObjectAddPropertyListenerBlock(device, &addr, queue, volBlock)
            volumeAddrs.append(addr)
        } else {
            for channel: UInt32 in [1, 2] {
                var chAddr = Self.mainVolumeAddress()
                chAddr.mElement = channel
                AudioObjectAddPropertyListenerBlock(device, &chAddr, queue, volBlock)
                volumeAddrs.append(chAddr)
            }
        }

        let muteBlk: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.emit() }
        }
        muteBlock = muteBlk
        var muteAddr = Self.muteAddress()
        AudioObjectAddPropertyListenerBlock(device, &muteAddr, queue, muteBlk)

        installedDevice = device
        installedVolumeAddrs = volumeAddrs
    }

    /// Tears down whatever `installListeners()` last installed on
    /// `installedDevice`. Safe no-op when nothing is installed. Must run
    /// before re-installing on a new default device, else the old device's
    /// listener blocks leak.
    private func removeListeners() {
        guard installedDevice != kAudioObjectUnknown else { return }

        if let volBlock = volumeBlock {
            for addr in installedVolumeAddrs {
                var mutableAddr = addr
                AudioObjectRemovePropertyListenerBlock(installedDevice, &mutableAddr, queue, volBlock)
            }
        }
        if let muteBlk = muteBlock {
            var muteAddr = Self.muteAddress()
            AudioObjectRemovePropertyListenerBlock(installedDevice, &muteAddr, queue, muteBlk)
        }

        installedDevice = AudioObjectID(kAudioObjectUnknown)
        installedVolumeAddrs = []
        volumeBlock = nil
        muteBlock = nil
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
                guard let self else { return }
                self.device = AudioService.defaultOutputDevice()
                self.installListeners()
                self.onDeviceChange?(self.currentDeviceSupportsVolume())
            }
        }
    }

    private func emit() {
        let level = currentVolume()
        let muted = currentMute()
        let origin: VolumeChangeOrigin
        if !hasEmitted {
            hasEmitted = true
            origin = .initial
        } else {
            let classified = Self.classifyOrigin(level: level, now: Date(), pending: pendingSelfWrite)
            if classified == .selfWrite {
                pendingSelfWrite = nil
            }
            origin = classified
        }
        onChange?(level, muted, origin)
    }

    private func currentVolume() -> Double {
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = Self.mainVolumeAddress()
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
        var address = Self.muteAddress()
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr && value != 0
    }
}
