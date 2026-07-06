import Foundation

/// Composes calendar events and weather into `model.calendar`, refreshing at
/// midnight and on a periodic timer.
@MainActor
final class CalendarController {
    private let model: NotchViewModel
    private let calendar = CalendarService()
    private let weather = WeatherService()

    private var events: [NotchEvent] = []
    private var currentWeather: WeatherSnapshot?
    private var refreshTimer: Timer?

    init(model: NotchViewModel) {
        self.model = model
    }

    func start() {
        calendar.onChange = { [weak self] events in
            self?.events = events
            self?.rebuild()
        }
        weather.onChange = { [weak self] snap in
            self?.currentWeather = snap
            self?.rebuild()
        }
        calendar.start()
        weather.start()
        rebuild()

        // Hourly refresh keeps the date/weather current across day boundaries.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.calendar.reload()
                self?.weather.start()
            }
        }
    }

    private func rebuild() {
        model.calendar = CalendarSnapshot(
            date: Date(),
            events: events,
            weatherText: currentWeather?.text,
            weatherSymbol: currentWeather?.symbol,
            temperature: currentWeather?.temperature
        )
    }
}
