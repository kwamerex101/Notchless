import Foundation

/// Which apps' now-playing info is surfaced in the notch: every media app
/// (`.systemWide`, the default — no behavior change from before this
/// feature), or only apps explicitly allow-listed in `.specificApps`.
enum NowPlayingSource: String, CaseIterable, Codable, StoredValue {
    case systemWide, specificApps
    var displayName: String { self == .systemWide ? "System-wide" : "Specific Apps" }
}

/// Pure filtering helpers for the Now Playing music-source restriction
/// (MediaMate parity: "System-wide" vs "Specific Apps" + an Allowed Apps
/// list). Kept free of `MediaController`/`SettingsStore` so it's trivially
/// unit-testable; `MediaController` calls into this from `provider.onChange`.
enum NowPlayingFilter {
    /// Whether a track from `bundleID` should be shown given the source mode.
    static func shouldAccept(bundleID: String?, source: NowPlayingSource, allowed: [String]) -> Bool {
        switch source {
        case .systemWide:
            return true
        case .specificApps:
            return bundleID.map { allowed.contains($0) } ?? false
        }
    }

    /// Record a seen bundle id at the front, de-duplicated, capped to `cap`.
    static func addSeen(_ id: String, to list: [String], cap: Int = 20) -> [String] {
        var result = list.filter { $0 != id }
        result.insert(id, at: 0)
        if result.count > cap { result.removeLast(result.count - cap) }
        return result
    }
}
