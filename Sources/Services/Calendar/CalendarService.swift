import EventKit
import SwiftUI

/// Reads today's events from EventKit. Requests calendar access at runtime;
/// yields an empty list if denied. See PLAN.md Phase 5.
@MainActor
final class CalendarService {
    var onChange: (([NotchEvent]) -> Void)?
    /// Reports whether calendar access is currently denied/restricted, so the
    /// UI can distinguish "no events" from "no permission".
    var onAuthDenied: ((Bool) -> Void)?

    private let store = EKEventStore()
    private var observing = false

    func start() {
        requestAccessAndLoad()
        NotificationCenter.default.addObserver(
            self, selector: #selector(storeChanged),
            name: .EKEventStoreChanged, object: store
        )
    }

    private func requestAccessAndLoad() {
        // Surface the current status immediately, then refine after the prompt.
        let status = EKEventStore.authorizationStatus(for: .event)
        onAuthDenied?(status == .denied || status == .restricted)
        store.requestFullAccessToEvents { [weak self] granted, _ in
            Task { @MainActor in
                guard let self else { return }
                self.onAuthDenied?(!granted)
                if granted { self.reload() } else { self.onChange?([]) }
            }
        }
    }

    @objc private func storeChanged() {
        reload()
    }

    func reload() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay || calendar.isDateInToday($0.startDate) }
            .sorted { $0.startDate < $1.startDate }
            .map { ev in
                NotchEvent(
                    id: ev.eventIdentifier ?? UUID().uuidString,
                    title: ev.title ?? "Event",
                    start: ev.startDate,
                    end: ev.endDate,
                    isAllDay: ev.isAllDay,
                    color: Color(nsColor: ev.calendar.color ?? .systemPink)
                )
            }
        onChange?(events)
    }
}

private extension EKCalendar {
    var color: NSColor? { NSColor(cgColor: cgColor) }
}
