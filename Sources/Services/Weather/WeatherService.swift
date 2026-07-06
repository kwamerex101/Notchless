import CoreLocation
import Foundation

struct WeatherSnapshot: Equatable {
    var temperature: String
    var text: String
    var symbol: String
}

/// Fetches current conditions from the free Open-Meteo API using CoreLocation.
/// Best-effort: yields nil if location or network is unavailable (calendar
/// still works without it). See PLAN.md Phase 5.
@MainActor
final class WeatherService: NSObject, CLLocationManagerDelegate {
    var onChange: ((WeatherSnapshot?) -> Void)?

    private let manager = CLLocationManager()

    func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        manager.stopUpdatingLocation()
        Task { await fetch(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.onChange?(nil) }
    }

    private func fetch(lat: Double, lon: Double) async {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code"
        guard let url = URL(string: urlString) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            let snap = WeatherSnapshot(
                temperature: "\(Int(decoded.current.temperature_2m.rounded()))°",
                text: Self.text(for: decoded.current.weather_code),
                symbol: Self.symbol(for: decoded.current.weather_code)
            )
            onChange?(snap)
        } catch {
            onChange?(nil)
        }
    }

    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable { let temperature_2m: Double; let weather_code: Int }
        let current: Current
    }

    /// WMO weather-code → label (see open-meteo docs).
    static func text(for code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1, 2: return "Partly Cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Foggy"
        case 51, 53, 55, 56, 57: return "Drizzle"
        case 61, 63, 65, 66, 67, 80, 81, 82: return "Rain"
        case 71, 73, 75, 77, 85, 86: return "Snow"
        case 95, 96, 99: return "Storms"
        default: return "—"
        }
    }

    static func symbol(for code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67, 80, 81, 82: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}
