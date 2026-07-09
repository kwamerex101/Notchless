import Foundation
import IOKit
import AppKit
import os

/// Drives the built-in Force Touch trackpad's Taptic Engine via the private
/// MultitouchSupport MTActuator API. All symbols are resolved at runtime with
/// dlopen/dlsym so a macOS release that drops them degrades to
/// `isAvailable == false` instead of failing at load. Thread-safe; called from
/// the event-tap thread.
final class TrackpadHapticEngine: HapticActuating {
    // MARK: Private-API surface (C signatures)
    private typealias CreateFn = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    private typealias OpenCloseFn = @convention(c) (CFTypeRef) -> Int32   // IOReturn
    private typealias ActuateFn = @convention(c) (CFTypeRef, Int32, UInt32, Float, Float) -> Int32

    private struct Symbols {
        let create: CreateFn
        let open: OpenCloseFn
        let close: OpenCloseFn
        let actuate: ActuateFn

        static func load() -> Symbols? {
            guard let handle = dlopen(
                "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
                RTLD_LAZY) else { return nil }
            guard
                let create = dlsym(handle, "MTActuatorCreateFromDeviceID"),
                let open = dlsym(handle, "MTActuatorOpen"),
                let close = dlsym(handle, "MTActuatorClose"),
                let actuate = dlsym(handle, "MTActuatorActuate")
            else { return nil }
            return Symbols(
                create: unsafeBitCast(create, to: CreateFn.self),
                open: unsafeBitCast(open, to: OpenCloseFn.self),
                close: unsafeBitCast(close, to: OpenCloseFn.self),
                actuate: unsafeBitCast(actuate, to: ActuateFn.self))
        }
    }

    /// Built-in waveform IDs. Chosen from the commonly-used 1...6 range;
    /// confirmed by the on-device feel pass (weakest→strongest: 3, 4, 6).
    static func actuationID(for strength: HapticStrength) -> Int32 {
        switch strength {
        case .light: return 3
        case .medium: return 4
        case .strong: return 6
        }
    }

    /// The built-in trackpad's multitouch device ID from the IORegistry.
    private static func builtInTrackpadDeviceID() -> UInt64? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("AppleMultitouchDevice"),
            &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var entry: io_object_t = IOIteratorNext(iterator)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iterator) }
            if let value = IORegistryEntryCreateCFProperty(
                entry, "Multitouch ID" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? UInt64 {
                return value   // first multitouch device = the built-in trackpad
            }
        }
        return nil
    }

    /// Cheap capability check for the Settings pane: symbols + device present,
    /// no actuator opened.
    static func probeAvailability() -> Bool {
        Symbols.load() != nil && builtInTrackpadDeviceID() != nil
    }

    // MARK: State

    private struct Actuator {
        let ref: CFTypeRef
        let symbols: Symbols
    }
    private let lock = OSAllocatedUnfairLock<Actuator?>(initialState: nil)
    private let symbols: Symbols?
    private let deviceID: UInt64?
    private var wakeObserver: NSObjectProtocol?

    init() {
        symbols = Symbols.load()
        deviceID = Self.builtInTrackpadDeviceID()
        // The actuator can go stale across sleep; drop it so the next actuate reopens.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.invalidate() }
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        close()
    }

    var isAvailable: Bool { symbols != nil && deviceID != nil }

    func actuate(_ strength: HapticStrength) {
        guard let actuator = openIfNeeded() else { return }
        let result = actuator.symbols.actuate(
            actuator.ref, Self.actuationID(for: strength), 0, 0, 0)
        if result != 0 {   // kIOReturnSuccess == 0; stale after sleep/reconnect → reopen once
            invalidate()
            if let retry = openIfNeeded() {
                _ = retry.symbols.actuate(retry.ref, Self.actuationID(for: strength), 0, 0, 0)
            }
        }
    }

    func close() {
        invalidate()
    }

    // MARK: Lifecycle

    private func openIfNeeded() -> Actuator? {
        lock.withLock { current in
            if let current { return current }
            guard let symbols, let deviceID,
                  let ref = symbols.create(deviceID)?.takeRetainedValue(),
                  symbols.open(ref) == 0 else { return nil }
            let actuator = Actuator(ref: ref, symbols: symbols)
            current = actuator
            return actuator
        }
    }

    private func invalidate() {
        lock.withLock { current in
            if let current { _ = current.symbols.close(current.ref) }
            current = nil
        }
    }
}
