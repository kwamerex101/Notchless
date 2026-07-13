import AppKit

/// Stateful suppression of the system volume/brightness OSD: while active,
/// pauses `OSDUIHelper` via SIGSTOP once (and keeps it stopped, catching
/// launchd respawns with a watchdog), then SIGCONTs it on deactivation, quit,
/// or crash. Replaces the old per-event `suppress()`/`restore()` pair, which
/// shelled `pgrep` on the main thread inside every volume/brightness
/// callback, lost the race against the native OSD, and wasn't crash-safe.
///
/// **Known, accepted tradeoff:** `OSDUIHelper` also drives the Caps-Lock and
/// keyboard-backlight OSDs, so while suppression is active those are
/// suppressed too (see the Phase 1 grill decision).
///
/// Default OFF; gated behind `SettingsStore.suppressSystemOSD` and driven by
/// `HUDController`. Not hard-blocked by OS version — the user must be able
/// to toggle it to test — but `testedMacOSMajors`/`isValidatedOnCurrentOS`
/// let the UI warn when running on an unvalidated major.
@MainActor
final class OSDSuppressor {
    static let shared = OSDSuppressor()

    /// macOS major versions this suppression strategy has been validated on.
    static let testedMacOSMajors: Set<Int> = [14, 15]

    /// Whether the running OS's major version is in `testedMacOSMajors`.
    static var isValidatedOnCurrentOS: Bool {
        testedMacOSMajors.contains(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    private(set) var isActive = false

    private let signaller: ProcessSignaller
    private let processName: String
    private let watchdogInterval: TimeInterval
    private let enumerationRunner: (@escaping () -> [pid_t], @escaping ([pid_t]) -> Void) -> Void

    private var suppressedPIDs: Set<pid_t> = []
    private var watchdogTimer: Timer?

    /// - Parameter enumerationRunner: how PID enumeration hops off the main
    ///   thread and delivers its result back. Defaults to a real background
    ///   dispatch + hop-back-to-main; tests inject a synchronous runner so
    ///   `activate()`/`deactivate()`/watchdog ticks can be asserted on
    ///   immediately without spinning the run loop.
    init(signaller: ProcessSignaller = RealProcessSignaller(),
         processName: String = "OSDUIHelper",
         watchdogInterval: TimeInterval = 2.0,
         enumerationRunner: @escaping (@escaping () -> [pid_t], @escaping ([pid_t]) -> Void) -> Void = OSDSuppressor.dispatchOffMain) {
        self.signaller = signaller
        self.processName = processName
        self.watchdogInterval = watchdogInterval
        self.enumerationRunner = enumerationRunner
    }

    /// Production off-main hop: runs `work` (the `pgrep` shell-out) on a
    /// background queue, then delivers the result back on main.
    nonisolated private static func dispatchOffMain(_ work: @escaping () -> [pid_t], completion: @escaping ([pid_t]) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let result = work()
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Idempotent. Enumerates `OSDUIHelper` PIDs off the main thread, SIGSTOPs
    /// each, caches them, and starts the respawn watchdog. Enumeration only
    /// happens here and on watchdog ticks — never per HUD event.
    func activate() {
        guard !isActive else { return }
        isActive = true
        OSDCrashGuard.installOnce()
        suppressNewPIDs()
        startWatchdog()
    }

    /// Idempotent. SIGCONTs every cached PID, clears the cache, and stops the
    /// watchdog.
    func deactivate() {
        guard isActive else { return }
        isActive = false
        stopWatchdog()
        let pids = suppressedPIDs
        suppressedPIDs.removeAll()
        OSDCrashGuard.sync(suppressedPIDs)
        for pid in pids { signaller.signal(SIGCONT, to: pid) }
    }

    /// Test seam: triggers one watchdog pass synchronously (with a
    /// synchronous `enumerationRunner`) instead of waiting on the real timer.
    func tickWatchdogForTesting() {
        suppressNewPIDs()
    }

    /// Enumerates the process off-main, then SIGSTOPs + caches any PID not
    /// already suppressed. Used by both `activate()` and the watchdog, so a
    /// launchd respawn is caught within one `watchdogInterval`.
    private func suppressNewPIDs() {
        let name = processName
        let signaller = signaller
        enumerationRunner({ signaller.pids(ofProcessNamed: name) }) { [weak self] pids in
            guard let self else { return }
            for pid in pids where !self.suppressedPIDs.contains(pid) {
                self.signaller.signal(SIGSTOP, to: pid)
                self.suppressedPIDs.insert(pid)
            }
            OSDCrashGuard.sync(self.suppressedPIDs)
        }
    }

    private func startWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: watchdogInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.suppressNewPIDs() }
        }
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }
}

/// Process-global, async-signal-safe mirror of `OSDSuppressor`'s suppressed
/// PIDs, plus the `atexit`/`SIGTERM`/`SIGINT` handlers that restore them.
///
/// Deliberately **not** `@MainActor` (not even part of `OSDSuppressor`):
/// signal handlers fire on whatever thread received the signal, outside any
/// actor the Swift runtime controls, and their bodies may call only
/// async-signal-safe functions. That means no Swift `Set`, no allocation, no
/// `pgrep`/`Process` — only a `kill(2)` loop over this cached raw C array.
/// The lack of synchronization between a concurrent `sync(_:)` write and a
/// handler read is an accepted tradeoff for a best-effort crash restore.
private enum OSDCrashGuard {
    private static let maxTrackedPIDs = 64
    private static let pids = UnsafeMutablePointer<pid_t>.allocate(capacity: maxTrackedPIDs)
    private static var count: Int32 = 0
    private static var installed = false

    /// Mirrors the live suppressed-PID cache into the process-global C array.
    /// Called from `OSDSuppressor` (main actor) whenever its cache changes.
    static func sync(_ suppressedPIDs: Set<pid_t>) {
        var i: Int32 = 0
        for pid in suppressedPIDs.prefix(maxTrackedPIDs) {
            pids[Int(i)] = pid
            i += 1
        }
        count = i
    }

    /// Installed once (on first `activate()`): restores every still-suppressed
    /// process on normal exit, SIGTERM, or SIGINT, so a crash/kill doesn't
    /// leave `OSDUIHelper` (and Caps-Lock/backlight OSDs) stopped forever.
    static func installOnce() {
        guard !installed else { return }
        installed = true
        atexit {
            OSDCrashGuard.restoreAllSignalSafe()
        }
        signal(SIGTERM) { _ in
            OSDCrashGuard.restoreAllSignalSafe()
            _exit(0)
        }
        signal(SIGINT) { _ in
            OSDCrashGuard.restoreAllSignalSafe()
            _exit(0)
        }
    }

    /// Async-signal-safe: only iterates the raw C array and calls `kill`.
    /// No `pgrep`, no `Process`, no Swift allocation.
    private static func restoreAllSignalSafe() {
        let n = Int(count)
        guard n > 0 else { return }
        for i in 0..<n {
            kill(pids[i], SIGCONT)
        }
    }
}
