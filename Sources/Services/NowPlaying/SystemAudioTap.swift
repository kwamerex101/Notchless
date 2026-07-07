import Foundation
import CoreAudio
import AudioToolbox
import OSLog

/// Captures system audio output via a CoreAudio process tap (macOS 14.2+),
/// runs it through the FFT analyzer, and publishes band levels to
/// `model.audio.musicSpectrum` so the now-playing visualizer reacts to real audio.
///
/// Capturing system audio needs the `NSAudioCaptureUsageDescription` TCC grant
/// (separate from the microphone one) — without it the OS hands the tap buffers
/// full of silence rather than failing, so there's nothing to catch at creation.
/// Worse, a tap created *before* that grant (or one that spontaneously goes
/// dormant) stays silent forever and can only be revived by a full teardown +
/// recreate. The `startDrain` silence watchdog does exactly that. If the tap
/// genuinely can't be created (older macOS, denied), we log and no-op, and the
/// visualizer falls back to its decorative animation.
@MainActor
final class SystemAudioTap {
    private let model: NotchViewModel
    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioObjectID = 0
    private var procID: AudioDeviceIOProcID?
    private var running = false

    /// Latest FFT bands and the raw peak amplitude from the realtime IO thread,
    /// drained to the UI at ~30 Hz (the IO callback fires far faster). Guarded by
    /// `bandsLock`. `latestPeak` is the true "is audio flowing" signal — unlike
    /// the auto-normalized/slow-release bands, it reads 0 the instant the tap
    /// goes silent, which the watchdog relies on.
    private let bandsLock = NSLock()
    private var latestBands: [CGFloat] = []
    private var latestPeak: Float = 0
    private var drainTimer: DispatchSourceTimer?

    /// Silence-watchdog bookkeeping (monotonic `systemUptime` seconds).
    private var lastSignalAt: TimeInterval = 0
    private var lastRecreateAt: TimeInterval = 0
    /// Recreates attempted in the current silence episode, and whether we've
    /// given up on it. Reset when audio flows again or the gate restarts the tap.
    private var recreateAttempts = 0
    private var gaveUp = false
    /// Raw peak below this counts as digital silence. Real audio — even quiet
    /// passages — sits well above it; a dormant tap delivers exactly 0.
    nonisolated static let silenceFloor: Float = 1e-4
    /// How long the tap may be silent while music plays before we recreate it.
    nonisolated static let silenceGrace: TimeInterval = 2.5
    /// Minimum gap between recreates, so a still-silent tap doesn't thrash.
    nonisolated static let recreateCooldown: TimeInterval = 5
    /// Recreates to try before giving up. A genuinely dormant tap recovers in
    /// one or two; beyond that the silence is real (paused, denied permission,
    /// wedged CoreAudio) and recreating only churns the audio engine — so we
    /// stop and let the visualizer fall back to its decorative animation.
    nonisolated static let maxRecreateAttempts = 2

    private static let log = Logger(subsystem: "com.rexdanquah.Notchless", category: "SystemAudioTap")

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
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr, tap != 0 else {
            Self.log.error("AudioHardwareCreateProcessTap failed — no live visualizer")
            return
        }
        tapID = tap

        guard let uid = tapUID(tap) else {
            Self.log.error("tap UID unavailable")
            teardown(); return
        }

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
            Self.log.error("AudioHardwareCreateAggregateDevice failed")
            teardown(); return
        }
        aggregateID = aggregate

        // The IO block runs on a realtime thread and only stashes the newest
        // bands + raw peak under a lock — no per-callback main-thread hop. A 30 Hz
        // timer drains that slot into the UI, so the visualizer updates smoothly
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
            let n = min(count, 2048)
            let bands = analyzer.bands(from: samples, count: n)
            var peak: Float = 0
            for i in 0..<n { let a = abs(samples[i]); if a > peak { peak = a } }
            lock.lock(); self.latestBands = bands; self.latestPeak = peak; lock.unlock()
        }
        guard status == noErr, let proc else {
            Self.log.error("AudioDeviceCreateIOProcIDWithBlock failed (status \(status))")
            teardown(); return
        }
        procID = proc

        guard AudioDeviceStart(aggregate, proc) == noErr else {
            Self.log.error("AudioDeviceStart failed")
            teardown(); return
        }
        // Grace the fresh tap: give it time to warm up (and, on first launch, for
        // the user to grant the audio-capture prompt) before the watchdog judges
        // it silent.
        latestPeak = 0
        lastSignalAt = ProcessInfo.processInfo.systemUptime
        startDrain()
        running = true
    }

    func stop() {
        teardown()
        // Fresh gate start should begin a clean silence episode. recreate()
        // deliberately does not reset these, so its attempt count survives.
        recreateAttempts = 0
        gaveUp = false
        model.audio.musicSpectrum = []
    }

    /// Drains the latest bands to the UI at ~30 Hz, skipping publishes when the
    /// levels barely moved so a steady tone doesn't churn the view. Also runs the
    /// silence watchdog on the raw peak.
    private func startDrain() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1.0 / 30.0)
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.bandsLock.lock()
                let bands = self.latestBands
                let peak = self.latestPeak
                self.bandsLock.unlock()

                // Silence watchdog: if music is playing yet the raw peak has read
                // silence past the grace window, the tap has gone dormant (or was
                // created before authorization). Recreating from scratch is the
                // only reliable recovery — but bounded: after a couple of failed
                // attempts the silence is real (paused, denied, wedged CoreAudio),
                // so we stop churning and fall back to the decorative animation.
                let now = ProcessInfo.processInfo.systemUptime
                if peak > Self.silenceFloor {
                    self.lastSignalAt = now
                    self.recreateAttempts = 0
                    self.gaveUp = false
                }
                let silentFor = now - self.lastSignalAt
                if !self.gaveUp,
                   Self.shouldRecreate(isPlaying: self.model.nowPlaying?.isPlaying == true,
                                       silentFor: silentFor,
                                       sinceLastRecreate: now - self.lastRecreateAt) {
                    self.lastRecreateAt = now
                    if self.recreateAttempts < Self.maxRecreateAttempts {
                        self.recreateAttempts += 1
                        Self.log.notice("tap silent \(silentFor, format: .fixed(precision: 1))s while playing — recreating (\(self.recreateAttempts)/\(Self.maxRecreateAttempts))")
                        DispatchQueue.main.async { [weak self] in self?.recreate() }
                    } else {
                        // Give up: stop churning CoreAudio and let the view fall
                        // back to its decorative animation (empty spectrum). The
                        // still-running tap can self-recover if audio returns, and
                        // the gate resets us on the next play/visibility change.
                        self.gaveUp = true
                        self.model.audio.musicSpectrum = []
                        Self.log.notice("tap still silent after \(Self.maxRecreateAttempts) recreates — giving up (decorative fallback)")
                    }
                    return
                }

                let current = self.model.audio.musicSpectrum
                guard Self.changed(bands, current) else { return }
                self.model.audio.musicSpectrum = bands
            }
        }
        timer.resume()
        drainTimer = timer
    }

    /// Whether the watchdog should recreate the tap: music is playing, we've had
    /// only silence past the grace window, and we're outside the recreate
    /// cooldown. Pure so the policy can be unit-tested without CoreAudio.
    nonisolated static func shouldRecreate(isPlaying: Bool,
                                           silentFor: TimeInterval,
                                           sinceLastRecreate: TimeInterval) -> Bool {
        isPlaying && silentFor > silenceGrace && sinceLastRecreate > recreateCooldown
    }

    /// Tear down and rebuild the tap + aggregate from scratch. A dormant or
    /// pre-authorization tap can't be revived in place — see the watchdog.
    private func recreate() {
        guard running else { return }
        teardown()
        start()
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
