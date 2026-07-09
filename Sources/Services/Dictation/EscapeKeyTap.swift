import AppKit

/// A consuming `esc` key tap, active only while dictation is recording. Unlike
/// the listen-only hotkey tap, this one returns nil for `esc` keyDown so the
/// keystroke does NOT leak to the frontmost app (which is the dictation target —
/// esc there would close sheets, exit full screen, etc.). Requires Accessibility.
@MainActor
final class EscapeKeyTap {
    var onEscape: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let escKeyCode: Int64 = 53

    func start() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let this = Unmanaged<EscapeKeyTap>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                MainActor.assumeIsolated { this.reenable() }
                return Unmanaged.passUnretained(event)
            }
            if type == .keyDown,
               event.getIntegerValueField(.keyboardEventKeycode) == this.escKeyCode {
                MainActor.assumeIsolated { this.onEscape?() }
                return nil // consume — esc does not reach the target app
            }
            return Unmanaged.passUnretained(event)
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap, // consuming, not listenOnly
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        ) else { return }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    private func reenable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}
