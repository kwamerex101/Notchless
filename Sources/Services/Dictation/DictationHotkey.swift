import AppKit

/// Hold-to-dictate global hotkey. Watches modifier-flag changes via a
/// listen-only event tap; when the chosen combo (default: right ⌥ Option held)
/// goes down it fires `onPress`, and on release `onRelease`. Requires
/// Accessibility permission; degrades to no-op if not granted.
@MainActor
final class DictationHotkey {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isDown = false

    /// The modifier that must be held to dictate. Right Option keeps the left
    /// modifiers free for normal shortcuts.
    private let triggerFlag: CGEventFlags = .maskAlternate
    private let triggerKeyCode: Int64 = 61  // kVK_RightOption

    func start() {
        guard AXIsProcessTrusted() else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
            // Retry once access is likely granted.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                if AXIsProcessTrusted() { self?.installTap() }
            }
            return
        }
        installTap()
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    private func installTap() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, _, event, refcon in
            if let refcon {
                let monitor = Unmanaged<DictationHotkey>.fromOpaque(refcon).takeUnretainedValue()
                MainActor.assumeIsolated { monitor.handle(event) }
            }
            return Unmanaged.passUnretained(event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
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

    private func handle(_ event: CGEvent) {
        // The specific key that changed is in the keycode field of a
        // flagsChanged event; combine with the current flag state.
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flagHeld = event.flags.contains(triggerFlag)

        if keyCode == triggerKeyCode {
            if flagHeld, !isDown {
                isDown = true
                onPress?()
            } else if !flagHeld, isDown {
                isDown = false
                onRelease?()
            }
        }
    }
}
