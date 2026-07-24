import Foundation

/// The notch sections that can be popped out as an independent floating
/// widget. A strict subset of `NotchActivity`.
enum WidgetKind: String, CaseIterable, Codable {
    case todos, goals, meeting

    /// The `NotchActivity` this widget mirrors when opened from the notch.
    var activity: NotchActivity {
        switch self {
        case .todos:   return .todos
        case .goals:   return .goals
        case .meeting: return .meeting
        }
    }

    /// Maps a `NotchActivity` to its widget-capable counterpart, or nil for
    /// activities that have no pop-out widget.
    init?(activity: NotchActivity) {
        switch activity {
        case .todos:   self = .todos
        case .goals:   self = .goals
        case .meeting: self = .meeting
        default:       return nil
        }
    }

    /// Human-readable title, sourced from `NotchActivity.tabLabel` rather
    /// than duplicating the strings here.
    var title: String { activity.tabLabel }
}
