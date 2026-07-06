import Foundation
import CoreAudio
import AudioToolbox

/// Captures system audio output via a CoreAudio process tap (macOS 14.2+),
/// runs it through the FFT analyzer, and publishes band levels to
/// `model.audio.musicSpectrum` so the now-playing visualizer reacts to real audio.
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

    /// Latest FFT bands from the realtime IO thread, drained to the UI at ~30 Hz
    /// (the IO callback fires far faster). Guarded by `bandsLock`.
    private let bandsLock = NSLock()
    private var latestBands: [CGFloat] = []
    private var drainTimer: DispatchSourceTimer?

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

        // The IO block runs on a realtime thread and only stashes the newest
        // bands under a lock — no per-callback main-thread hop. A 30 Hz timer
        // drains that slot into the UI, so the visualizer updates smoothly
        // without invalidating views ~90+ times a second.
        let analyzer = SpectrumAnalyzer(bandCount: 4)
        let lock = bandsLock
        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, nil) { [weak self] _, inInputData, _, _, _ in
            let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            guard let buffer = list.first, let raw = buffer.mData else { return }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            guard count > 0, let self else { return }
            let samples = raw.assumingMemoryBound(to: Float.self)
            let bands = analyzer.bands(from: samples, count: min(count, 2048))
            lock.lock(); self.latestBands = bands; lock.unlock()
        }
        guard status == noErr, let proc else { teardown(); return }
        procID = proc

        guard AudioDeviceStart(aggregate, proc) == noErr else { teardown(); return }
        startDrain()
        running = true
    }

    func stop() {
        teardown()
        model.audio.musicSpectrum = []
    }

    /// Drains the latest bands to the UI at ~30 Hz, skipping publishes when the
    /// levels barely moved so a steady tone doesn't churn the view.
    private func startDrain() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1.0 / 30.0)
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.bandsLock.lock()
                let bands = self.latestBands
                self.bandsLock.unlock()
                let current = self.model.audio.musicSpectrum
                guard Self.changed(bands, current) else { return }
                self.model.audio.musicSpectrum = bands
            }
        }
        timer.resume()
        drainTimer = timer
    }

    /// True when the band set differs enough to be worth republishing.
    private static func changed(_ new: [CGFloat], _ old: [CGFloat]) -> Bool {
        guard new.count == old.count else { return true }
        for i in new.indices where abs(new[i] - old[i]) >= 0.01 { return true }
        return false
    }

    private func teardown() {
        drainTimer?.cancel()
        drainTimer = nil
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
