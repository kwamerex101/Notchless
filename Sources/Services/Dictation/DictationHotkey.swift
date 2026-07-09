import AppKit

/// Hold-to-dictate global hotkey. Watches modifier-flag changes via a
/// listen-only event tap; when the chosen combo (default: right ⌥ Option held)
/// goes down it fires `onPress`, and on release `onRelease`. Requires
/// Accessibility permission; degrades to no-op if not granted.
@MainActor
final class DictationHotkey {
    var onPress: ((UUID?) -> Void)?
    var onRelease: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var trustTimer: Timer?
    private var didPromptForAccess = false

    private var bindings: [HotkeyBinding] = []
    private var active: HotkeyBinding?

    /// (Re)register the combos to watch — main first so it wins duplicate combos.
    func setBindings(_ bindings: [HotkeyBinding]) { self.bindings = bindings }

    func start() {
        if AXIsProcessTrusted() {
            installTap()
            return
        }
        // Prompt once, then poll until the user grants access — so the tap
        // installs the moment permission lands, without needing a relaunch.
        if !didPromptForAccess {
            didPromptForAccess = true
            DictationLog.log("hotkey: Accessibility NOT trusted — prompting, polling until granted")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        }
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    self.trustTimer = nil
                    self.installTap()
                }
            }
        }
    }

    func stop() {
        trustTimer?.invalidate()
        trustTimer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    private func installTap() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<DictationHotkey>.fromOpaque(refcon).takeUnretainedValue()
            // The system disables the tap if it ever times out or on user input;
            // re-enable it so hold-to-talk keeps working for the whole session.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                MainActor.assumeIsolated { monitor.reenable() }
                return Unmanaged.passUnretained(event)
            }
            MainActor.assumeIsolated { monitor.handle(event) }
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
        DictationLog.log("hotkey: event tap installed (\(bindings.count) bindings)")
    }

    private func reenable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
        DictationLog.log("hotkey: tap was disabled by system — re-enabled")
    }

    private func handle(_ event: CGEvent) {
        let match = HotkeyMatcher.match(held: event.flags, bindings: bindings)
        if let match, active == nil {
            active = match
            onPress?(match.id)
        } else if match == nil, active != nil {
            active = nil
            onRelease?()
        }
    }
}
