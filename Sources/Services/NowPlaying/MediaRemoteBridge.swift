import Foundation

/// Thin dynamic binding to the private MediaRemote framework. Loads lazily and
/// degrades to no-ops if the framework or its symbols are unavailable (e.g.
/// macOS 15.4+ where these calls are entitlement-gated — see PLAN.md §2, §5).
/// The correct long-term fix on gated systems is the mediaremote-adapter
/// helper; this binding covers systems where the direct calls still work.
final class MediaRemoteBridge {
    static let shared = MediaRemoteBridge()

    private var handle: UnsafeMutableRawPointer?

    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void
    private typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
    private typealias SendCommandFn = @convention(c) (Int32, CFDictionary?) -> Bool

    private var getInfo: GetInfoFn?
    private var register: RegisterFn?
    private var sendCommandFn: SendCommandFn?

    // Notification names (exported CFString constants).
    private(set) var infoDidChange: String?
    private(set) var isPlayingDidChange: String?

    var isAvailable: Bool { getInfo != nil }

    private init() {
        guard let h = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_NOW
        ) else { return }
        handle = h

        if let sym = dlsym(h, "MRMediaRemoteGetNowPlayingInfo") {
            getInfo = unsafeBitCast(sym, to: GetInfoFn.self)
        }
        if let sym = dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            register = unsafeBitCast(sym, to: RegisterFn.self)
        }
        if let sym = dlsym(h, "MRMediaRemoteSendCommand") {
            sendCommandFn = unsafeBitCast(sym, to: SendCommandFn.self)
        }
        infoDidChange = string(for: "kMRMediaRemoteNowPlayingInfoDidChangeNotification")
        isPlayingDidChange = string(for: "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification")
    }

    private func string(for symbol: String) -> String? {
        guard let h = handle, let sym = dlsym(h, symbol) else { return nil }
        let ptr = sym.assumingMemoryBound(to: Unmanaged<CFString>?.self)
        return ptr.pointee?.takeUnretainedValue() as String?
    }

    func registerForNotifications() {
        register?(DispatchQueue.main)
    }

    func fetchInfo(_ completion: @escaping (CFDictionary?) -> Void) {
        guard let getInfo else { completion(nil); return }
        getInfo(DispatchQueue.main, completion)
    }

    /// MRMediaRemoteCommand values: 0 play, 1 pause, 2 togglePlayPause,
    /// 4 nextTrack, 5 previousTrack.
    @discardableResult
    func send(command: Int32, userInfo: CFDictionary? = nil) -> Bool {
        sendCommandFn?(command, userInfo) ?? false
    }
}
