import Foundation
import CoreAudio
import AudioToolbox

/// Captures system audio output via a CoreAudio process tap (macOS 14.2+),
/// runs it through the FFT analyzer, and publishes band levels to
/// `model.musicSpectrum` so the now-playing visualizer reacts to real audio.
///
/// Everything is best-effort: if the tap can't be created (older macOS, denied,
/// unsupported), it silently no-ops and the visualizer falls back to its
/// decorative animation.
@MainActor
final class SystemAudioTap {
    private let model: NotchViewModel
    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioObjectID = 0
    private var procID: AudioDeviceIOProcID?
    private var running = false

    init(model: NotchViewModel) {
        self.model = model
    }

    func start() {
        guard !running else { return }
        guard #available(macOS 14.2, *) else { return }

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap: AudioObjectID = 0
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr, tap != 0 else { return }
        tapID = tap

        guard let uid = tapUID(tap) else { teardown(); return }

        let aggUID = "com.rexdanquah.Notchless.visualizer.\(UInt(bitPattern: ObjectIdentifier(self).hashValue))"
        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Notchless Visualizer",
            kAudioAggregateDeviceUIDKey: aggUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: uid, kAudioSubTapDriftCompensationKey: true]
            ],
        ]
        var aggregate: AudioObjectID = 0
        guard AudioHardwareCreateAggregateDevice(dict as CFDictionary, &aggregate) == noErr, aggregate != 0 else {
            teardown(); return
        }
        aggregateID = aggregate

        // The IO block runs on a realtime thread; the analyzer + publish closure
        // are the only state it touches, both thread-safe / hop to main.
        let analyzer = SpectrumAnalyzer(bandCount: 4)
        let publish: @Sendable ([CGFloat]) -> Void = { [weak model] bands in
            DispatchQueue.main.async { model?.musicSpectrum = bands }
        }
        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, nil) { _, inInputData, _, _, _ in
            let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            guard let buffer = list.first, let raw = buffer.mData else { return }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            guard count > 0 else { return }
            let samples = raw.assumingMemoryBound(to: Float.self)
            let bands = analyzer.bands(from: samples, count: min(count, 2048))
            publish(bands)
        }
        guard status == noErr, let proc else { teardown(); return }
        procID = proc

        guard AudioDeviceStart(aggregate, proc) == noErr else { teardown(); return }
        running = true
    }

    func stop() {
        teardown()
        model.musicSpectrum = []
    }

    private func teardown() {
        if let procID {
            if aggregateID != 0 { AudioDeviceStop(aggregateID, procID); AudioDeviceDestroyIOProcID(aggregateID, procID) }
            self.procID = nil
        }
        if aggregateID != 0 { AudioHardwareDestroyAggregateDevice(aggregateID); aggregateID = 0 }
        if tapID != 0 {
            if #available(macOS 14.2, *) { AudioHardwareDestroyProcessTap(tapID) }
            tapID = 0
        }
        running = false
    }

    private func tapUID(_ tap: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var cfUID: Unmanaged<CFString>?
        let status = AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &cfUID)
        guard status == noErr, let cfUID else { return nil }
        return cfUID.takeRetainedValue() as String
    }
}
