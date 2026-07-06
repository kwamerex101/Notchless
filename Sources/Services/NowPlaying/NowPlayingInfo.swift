import AppKit

/// A snapshot of the system's currently-playing media.
struct NowPlayingInfo: Equatable {
    var title: String
    var artist: String
    var album: String?
    var artwork: NSImage?
    var isPlaying: Bool
    var elapsed: TimeInterval
    var duration: TimeInterval
    var bundleIdentifier: String?
    var appName: String?
    var canShuffle: Bool = true

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    static func time(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let total = Int(t.rounded())
        let m = total / 60, s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    var elapsedText: String { Self.time(elapsed) }
    var remainingText: String { "-" + Self.time(max(0, duration - elapsed)) }

    static func == (lhs: NowPlayingInfo, rhs: NowPlayingInfo) -> Bool {
        lhs.title == rhs.title &&
        lhs.artist == rhs.artist &&
        lhs.isPlaying == rhs.isPlaying &&
        abs(lhs.elapsed - rhs.elapsed) < 0.5 &&
        lhs.duration == rhs.duration &&
        lhs.bundleIdentifier == rhs.bundleIdentifier
    }
}

/// Transport commands a now-playing provider can execute.
enum MediaCommand {
    case playPause
    case next
    case previous
    case toggleShuffle
    case seek(TimeInterval)
}

/// Something that surfaces now-playing info and accepts transport commands.
@MainActor
protocol NowPlayingProvider: AnyObject {
    var onChange: ((NowPlayingInfo?) -> Void)? { get set }
    func start()
    func stop()
    func send(_ command: MediaCommand)
}
