import AppKit

/// Which special media key was pressed.
enum MediaKey {
    case brightnessUp, brightnessDown
    case soundUp, soundDown, mute
}

/// Listen-only CGEventTap for the hardware media keys, used to trigger the
/// brightness HUD (and, as a backup, the sound HUD). Requires Accessibility
/// permission at runtime; degrades to no-op if not granted. See PLAN.md §5.
@MainActor
final class MediaKeyTap {
    var onKey: ((MediaKey) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // NX_KEYTYPE_* constants from IOKit/hidsystem/ev_keymap.h
    private static let soundUp = 0, soundDown = 1, mute = 7, brightUp = 2, brightDown = 3
    private static let nxSysDefined: CGEventType = CGEventType(rawValue: 14)! // NSSystemDefined

    func start() {
        guard AXIsProcessTrusted() else {
            requestAccessibility()
            return
        }
        installTap()
    }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private func installTap() {
        let mask = CGEventMask(1 << Self.nxSysDefined.rawValue)
        let callback: CGEventTapCallBack = { _, _, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { tap.handle(event) }
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

    private func handle(_ cgEvent: CGEvent) {
        guard let nsEvent = NSEvent(cgEvent: cgEvent),
              nsEvent.subtype.rawValue == 8 else { return } // NSEventSubtypeScreenChanged==8 == aux keys
        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF0000) >> 16
        let keyState = (data1 & 0x0000FF00) >> 8
        let keyDown = keyState == 0x0A
        guard keyDown else { return }

        switch keyCode {
        case Self.brightUp: onKey?(.brightnessUp)
        case Self.brightDown: onKey?(.brightnessDown)
        case Self.soundUp: onKey?(.soundUp)
        case Self.soundDown: onKey?(.soundDown)
        case Self.mute: onKey?(.mute)
        default: break
        }
    }
}
