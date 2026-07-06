import SwiftUI

/// A single calendar event shown in the notch.
struct NotchEvent: Equatable, Identifiable {
    let id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var color: Color
}

/// Everything the calendar/duo panels need for "today".
struct CalendarSnapshot: Equatable {
    var date: Date
    var events: [NotchEvent]
    var weatherText: String?
    var weatherSymbol: String?
    var temperature: String?
    /// True when calendar access is denied/restricted — the panel shows a
    /// "grant access" prompt instead of pretending the day is clear.
    var authDenied: Bool = false

    var hasEvents: Bool { !events.isEmpty }

    var weekdayCaps: String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }

    var dayNumber: String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }

    var monthCaps: String {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f.string(from: date).uppercased()
    }
}
