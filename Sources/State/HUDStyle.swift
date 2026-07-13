import Foundation

/// The visual presentation of the volume/brightness HUD. `.notch` is the
/// current notch-integrated HUD (the default, and the only style
/// `HUDPresenter` routes into the notch); `.classic`, `.ios`, `.circular`
/// are floating pills MediaMate-style, rendered at `SettingsStore.hudPosition`.
enum HUDStyle: String, CaseIterable, Codable, StoredValue {
    case notch, classic, ios, circular

    var displayName: String {
        switch self {
        case .notch: return "Notch"
        case .classic: return "Classic"
        case .ios: return "iOS"
        case .circular: return "Circular"
        }
    }
}

/// How `CircularHUDView` renders its progress ring.
enum HUDIndicator: String, CaseIterable, Codable, StoredValue {
    case line, dot

    var displayName: String { self == .line ? "Line" : "Dot" }
}
