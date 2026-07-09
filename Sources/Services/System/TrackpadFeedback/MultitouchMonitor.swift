import AppKit
import os

// MARK: - Private MultitouchSupport contact-frame surface

private typealias MTDeviceRef = UnsafeMutableRawPointer

private struct MTPoint { var x: Float; var y: Float }
private struct MTVector { var position: MTPoint; var velocity: MTPoint }

/// Reference MTTouch layout (undocumented; stable since ~10.5, per
/// OpenMultitouchSupport / MiddleClick). VALIDATED on-device in Task 7 — a
/// one-field-off mirror silently decodes garbage.
private struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32
    var fingerID: Int32
    var handID: Int32
    var normalizedVector: MTVector
    var zTotal: Float
    var field9: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absoluteVector: MTVector
    var field14: Int32
    var field15: Int32
    var zDensity: Float
}

// NOTE (Task 4 compile fix): the touches parameter is `UnsafeRawPointer?`
// rather than `UnsafeMutablePointer<MTTouch>?` as written in the brief.
// Swift 6.3 rejects a `@convention(c)` function type whose parameter is a
// typed pointer to a non-ObjC-representable Swift struct ("... is not
// representable in Objective-C, so it cannot be used with '@convention(c)'"),
// even though the struct itself is a valid C-layout-compatible type. Using an
// untyped `UnsafeRawPointer` for the C ABI boundary and rebinding to `MTTouch`
// inside the callback (see `frameCallback`) sidesteps the check without
// changing the struct layout, decoding, or any other behavior from the brief.
private typealias MTContactCallback = @convention(c)
    (MTDeviceRef?, UnsafeRawPointer?, Int32, Double, Int32) -> Int32

private struct MTSymbols {
    let createDefault: @convention(c) () -> MTDeviceRef?
    let register: @convention(c) (MTDeviceRef, MTContactCallback) -> Void
    let unregister: @convention(c) (MTDeviceRef, MTContactCallback) -> Void
    let start: @convention(c) (MTDeviceRef, Int32) -> Void
    let stop: @convention(c) (MTDeviceRef) -> Void

    static func load() -> MTSymbols? {
        guard let h = dlopen(
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
            RTLD_LAZY) else { return nil }
        guard
            let c = dlsym(h, "MTDeviceCreateDefault"),
            let r = dlsym(h, "MTRegisterContactFrameCallback"),
            let u = dlsym(h, "MTUnregisterContactFrameCallback"),
            let s = dlsym(h, "MTDeviceStart"),
            let p = dlsym(h, "MTDeviceStop")
        else { return nil }
        return MTSymbols(
            createDefault: unsafeBitCast(c, to: (@convention(c) () -> MTDeviceRef?).self),
            register: unsafeBitCast(r, to: (@convention(c) (MTDeviceRef, MTContactCallback) -> Void).self),
            unregister: unsafeBitCast(u, to: (@convention(c) (MTDeviceRef, MTContactCallback) -> Void).self),
            start: unsafeBitCast(s, to: (@convention(c) (MTDeviceRef, Int32) -> Void).self),
            stop: unsafeBitCast(p, to: (@convention(c) (MTDeviceRef) -> Void).self))
    }
}

// MARK: - Monitor

/// Streams trackpad contact frames from the private MultitouchSupport device,
/// runs them through the pure recognizer, and fires the shared feedback core.
/// Observe-only. The C callback has no refcon, so frames are routed via a
/// static registry (device pointer → weak monitor); the weak lookup is the
/// use-after-free guard for a frame in flight after stop().
final class MultitouchMonitor {
    private let core: TrackpadFeedbackCore
    private var recognizer: MultitouchGestureRecognizer
    private let symbols: MTSymbols?
    private var device: MTDeviceRef?
    private var wakeObserver: NSObjectProtocol?

    private final class Box { weak var monitor: MultitouchMonitor?; init(_ m: MultitouchMonitor) { monitor = m } }
    private static let registry = OSAllocatedUnfairLock<[UnsafeRawPointer: Box]>(initialState: [:])

    init(core: TrackpadFeedbackCore, tuning: GestureTuning) {
        self.core = core
        self.recognizer = MultitouchGestureRecognizer(tuning: tuning)
        self.symbols = MTSymbols.load()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.reopen() }
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        stop()
    }

    /// Cheap capability check for the Settings pane: symbols present (device
    /// creation happens at start()).
    static func probeAvailability() -> Bool { MTSymbols.load() != nil }

    var isRunning: Bool { device != nil }

    func start() -> Bool {
        guard device == nil, let symbols, let dev = symbols.createDefault() else { return false }
        device = dev
        Self.registry.withLock { $0[UnsafeRawPointer(dev)] = Box(self) }
        symbols.register(dev, Self.frameCallback)
        symbols.start(dev, 0)
        return true
    }

    func stop() {
        guard let dev = device, let symbols else { device = nil; return }
        symbols.stop(dev)
        symbols.unregister(dev, Self.frameCallback)
        Self.registry.withLock { $0[UnsafeRawPointer(dev)] = nil }
        device = nil
    }

    private func reopen() {
        guard isRunning else { return }
        stop()
        _ = start()
    }

    // Called on the MT callback thread (serial). No @MainActor access.
    fileprivate func handleFrame(_ touches: [FingerTouch], timestamp: TimeInterval) {
        if recognizer.recognize(touches: touches, timestamp: timestamp) != nil {
            core.handleGesture()
        }
    }

    private static let frameCallback: MTContactCallback = { device, touches, numTouches, timestamp, _ in
        guard let device, let touches, numTouches > 0 else { return 0 }
        let monitor = registry.withLock { $0[UnsafeRawPointer(device)]?.monitor }
        guard let monitor else { return 0 }   // frame after stop() → dropped safely
        let typedTouches = touches.assumingMemoryBound(to: MTTouch.self)
        var decoded: [FingerTouch] = []
        decoded.reserveCapacity(Int(numTouches))
        for i in 0..<Int(numTouches) {
            let t = typedTouches[i]
            decoded.append(FingerTouch(
                x: Double(t.normalizedVector.position.x),
                y: Double(t.normalizedVector.position.y),
                id: Int(t.identifier),
                state: Int(t.state)))
        }
        monitor.handleFrame(decoded, timestamp: timestamp)
        return 0
    }
}
