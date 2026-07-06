import SwiftUI

/// Which idle activity the notch shows when nothing transient is happening.
enum NotchActivity: String, CaseIterable, Codable {
    /// Live Activities: automatically show whatever is happening right now
    /// (media playing, …) and nothing when nothing is — like iOS.
    case auto
    case none
    case playing
    case calendar
    case duo
    case dictation
    case battery
    case stats
    case timer
    case clipboard
    case privacy
}

/// The two hardware HUDs that replace the system OSD.
enum HUDKind: Equatable {
    case sound(level: Double, muted: Bool)
    case display(level: Double)

    var label: String {
        switch self {
        case .sound: return "Sound"
        case .display: return "Display"
        }
    }

    var systemImage: String {
        switch self {
        case let .sound(_, muted): return muted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .display: return "sun.max.fill"
        }
    }

    var level: Double {
        switch self {
        case let .sound(level, _): return level
        case let .display(level): return level
        }
    }
}

/// A transient notch expansion (battery, connectivity, focus…).
struct TransientNotification: Equatable, Identifiable {
    let id = UUID()
    var systemImage: String
    var tint: Color
    var title: String
    var subtitle: String?
    var trailingText: String?
    /// Seconds to remain visible before auto-collapsing.
    var duration: TimeInterval = 2.4

    static func == (lhs: TransientNotification, rhs: TransientNotification) -> Bool {
        lhs.id == rhs.id
    }
}

/// The user's interaction level with the notch.
enum Interaction: Equatable {
    case collapsed
    case hovering
    case expanded
}

/// What kind of content the notch is currently presenting, after priority
/// resolution. This is what the view renders.
enum NotchContent: Equatable {
    case bare
    case idle(NotchActivity)
    case hud(HUDKind)
    case notification(TransientNotification)
    case expanded(NotchActivity)
    case fileTray(expanded: Bool)
    case mirror
    case dictation(DictationPhase)
}
