import AppKit
import CoreGraphics
import QuartzCore

/// Passive, listen-only CGEventTap for scroll + left click, running its own
/// runloop thread so feedback latency never depends on the main thread. Every
/// event is passed through untouched. Requires Accessibility trust — creation
/// fails without it, which `start()` reports via its return value.
///
/// Threading (see CLAUDE.md gotcha): the tap callback runs on the monitor's
/// thread and calls only `TrackpadFeedbackCore` (internally locked). It never
/// touches @MainActor state.
final class TrackpadEventMonitor {
    private let core: TrackpadFeedbackCore
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var thread: Thread?
    private var threadRunLoop: CFRunLoop?
    /// Signaled by the monitor thread once `CFRunLoopRun()` returns, so `stop()`
    /// can block until no more callbacks can fire. Essential because the tap
    /// holds an unretained pointer to `self` — a callback in flight after `self`
    /// deinits would be a use-after-free.
    private var threadFinished: DispatchSemaphore?

    init(core: TrackpadFeedbackCore) {
        self.core = core
    }

    deinit {
        // Backstop: if an owner drops the monitor without calling stop() (Task 8's
        // controller does `monitor = nil` on teardown), join the tap thread here so
        // its callback can't run on freed memory.
        stop()
    }

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                Unmanaged<TrackpadEventMonitor>.fromOpaque(refcon)
                    .takeUnretainedValue().handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon)
        else { return false }   // typically: Accessibility not granted

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = source

        // Capture the semaphore locally so the thread signals it regardless of
        // whether `self` survived (weak-self may be nil by the time the runloop
        // exits during deinit).
        let finished = DispatchSemaphore(value: 0)
        self.threadFinished = finished
        // Gate `start()` until the thread has assigned `threadRunLoop` and added
        // the source. Without this, a `stop()`/`deinit` racing an unstarted thread
        // would find `threadRunLoop == nil` (nothing to CFRunLoopStop) and then
        // block forever in `finished.wait()` — an unrecoverable main-thread freeze.
        let ready = DispatchSemaphore(value: 0)

        let thread = Thread { [weak self] in
            self?.threadRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            ready.signal()   // threadRunLoop is now set + source added
            CFRunLoopRun()   // exits via CFRunLoopStop in stop()
            finished.signal()
        }
        thread.name = "com.rexdanquah.notchless.trackpad-tap"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
        ready.wait()   // only on this thread-spawning path — see early returns above
        return true
    }

    func stop() {
        // Idempotent / safe when never started: no thread means nothing to join.
        guard let thread else { return }

        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let threadRunLoop { CFRunLoopStop(threadRunLoop) }

        // Join the monitor thread so no callback can fire after stop() returns —
        // but never wait from the tap thread itself, or we'd deadlock waiting for
        // a runloop that can only exit once this call returns.
        if Thread.current !== thread {
            threadFinished?.wait()
        }

        tap = nil
        source = nil
        self.thread = nil
        threadRunLoop = nil
        threadFinished = nil
    }

    // MARK: - Tap callback (monitor thread)

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .scrollWheel:
            // Trackpads send continuous (pixel-precise) scrolls; classic mouse
            // wheels don't. Only trackpad scrolls get detent feedback.
            guard event.getIntegerValueField(.scrollWheelEventIsContinuous) == 1 else { return }
            var delta = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            if delta == 0 {
                delta = event.getDoubleValueField(.scrollWheelEventDeltaAxis1) * 10
            }
            core.handleScroll(delta: delta, timestamp: CACurrentMediaTime())
        case .leftMouseDown:
            core.handleClick(down: true)
        case .leftMouseUp:
            core.handleClick(down: false)
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The OS can pause slow taps; ours is listen-only and cheap — resume.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        default:
            break
        }
    }
}
