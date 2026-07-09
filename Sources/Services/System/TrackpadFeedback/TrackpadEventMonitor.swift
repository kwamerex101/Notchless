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

    init(core: TrackpadFeedbackCore) {
        self.core = core
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

        let thread = Thread { [weak self] in
            self?.threadRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFRunLoopRun()   // exits via CFRunLoopStop in stop()
        }
        thread.name = "com.rexdanquah.notchless.trackpad-tap"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let threadRunLoop { CFRunLoopStop(threadRunLoop) }
        tap = nil
        source = nil
        thread = nil
        threadRunLoop = nil
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
