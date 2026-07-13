import Foundation

/// One button in the Now Playing transport row.
enum TransportButtonKind: Equatable {
    case shuffle
    case rewind15
    case previous
    case playPause
    case next
    case forward15
}

/// Pure resolver for which transport buttons appear, and in what order,
/// given the MediaMate-parity settings `npShowShuffle`/`npShowSkip15`.
/// `previous`/`playPause`/`next` are always present; `shuffle` is prepended
/// when enabled; `rewind15`/`forward15` bookend the core three when enabled.
enum NowPlayingTransport {
    static func ordered(showShuffle: Bool, showSkip15: Bool) -> [TransportButtonKind] {
        (showShuffle ? [.shuffle] : [])
            + (showSkip15 ? [.rewind15] : [])
            + [.previous, .playPause, .next]
            + (showSkip15 ? [.forward15] : [])
    }
}
