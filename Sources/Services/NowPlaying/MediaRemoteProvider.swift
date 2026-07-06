import AppKit

/// Now-playing provider backed by `MediaRemoteBridge`. Parses the info
/// dictionary into `NowPlayingInfo` and forwards transport commands.
@MainActor
final class MediaRemoteProvider: NowPlayingProvider {
    var onChange: ((NowPlayingInfo?) -> Void)?

    private let bridge = MediaRemoteBridge.shared
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard bridge.isAvailable else {
            onChange?(nil)
            return
        }
        bridge.registerForNotifications()

        let center = NotificationCenter.default
        for name in [bridge.infoDidChange, bridge.isPlayingDidChange].compactMap({ $0 }) {
            let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append(token)
        }
        refresh()
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    func send(_ command: MediaCommand) {
        switch command {
        case .playPause: bridge.send(command: 2)
        case .next: bridge.send(command: 4)
        case .previous: bridge.send(command: 5)
        case .toggleShuffle: break // command id varies by OS; wired later
        case .seek: break          // MRMediaRemoteSetElapsedTime binding TBD
        }
    }

    private func refresh() {
        bridge.fetchInfo { [weak self] dict in
            MainActor.assumeIsolated {
                self?.onChange?(Self.parse(dict))
            }
        }
    }

    private static func parse(_ dict: CFDictionary?) -> NowPlayingInfo? {
        guard let dict = dict as? [String: Any] else { return nil }

        let title = dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String
        guard let title, !title.isEmpty else { return nil }

        let artist = dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
        let album = dict["kMRMediaRemoteNowPlayingInfoAlbum"] as? String
        let duration = dict["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0
        let elapsed = dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0
        let rate = dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0

        var artwork: NSImage?
        if let data = dict["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
            artwork = NSImage(data: data)
        }

        return NowPlayingInfo(
            title: title,
            artist: artist,
            album: album,
            artwork: artwork,
            isPlaying: rate > 0,
            elapsed: elapsed,
            duration: duration,
            bundleIdentifier: nil,
            appName: nil
        )
    }
}
