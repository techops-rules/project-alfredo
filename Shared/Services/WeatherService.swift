import Foundation

// MARK: - Weather Data Models

struct HourForecast: Identifiable {
    let id = UUID()
    let hour: Int
    let temp: Double
    let code: Int
    let time: Date
}

struct MoonPhase {
    let age: Double          // 0–29.53 days
    let illumination: Double // 0–1
    let isWaxing: Bool
    let emoji: String
}

struct WeatherData {
    let temp: Double
    let code: Int
    let wind: Double
    let hi: Double
    let lo: Double
    let desc: String
    let sunrise: Date
    let sunset: Date
    let hourly: [HourForecast]
    let moonPhase: MoonPhase
    let fetchedAt: Date
}

// MARK: - Weather Service

@MainActor
@Observable
final class WeatherService {
    static let shared = WeatherService()

    private(set) var current: WeatherData?
    private(set) var lastError: String?

    private var fetchTimer: Timer?
    private let fetchInterval: TimeInterval = 600 // 10 minutes

    // Default = Allentown, PA 18104. Overridable via LocationPreferences
    // (zip lookup or current-location) persisted to UserDefaults.
    static let defaultLat = 40.5994
    static let defaultLon = -75.5394
    static let defaultLabel = "18104"

    private var lat: Double {
        let stored = UserDefaults.standard.double(forKey: "weather.lat")
        return stored == 0 ? Self.defaultLat : stored
    }
    private var lon: Double {
        let stored = UserDefaults.standard.double(forKey: "weather.lon")
        return stored == 0 ? Self.defaultLon : stored
    }
    var locationLabel: String {
        UserDefaults.standard.string(forKey: "weather.label") ?? Self.defaultLabel
    }

    private init() {}

    func start() {
        fetch()
        fetchTimer?.invalidate()
        fetchTimer = Timer.scheduledTimer(withTimeInterval: fetchInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fetch() }
        }
    }

    func stop() {
        fetchTimer?.invalidate()
        fetchTimer = nil
    }

    func fetch() {
        Task {
            do {
                let data = try await fetchFromAPI()
                self.current = data
                self.lastError = nil
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }

    /// Update the stored location and re-fetch.
    func setLocation(lat: Double, lon: Double, label: String) {
        UserDefaults.standard.set(lat, forKey: "weather.lat")
        UserDefaults.standard.set(lon, forKey: "weather.lon")
        UserDefaults.standard.set(label, forKey: "weather.label")
        fetch()
    }

    // MARK: - Open-Meteo API

    private func fetchFromAPI() async throws -> WeatherData {
        let urlString = "https://api.open-meteo.com/v1/forecast"
            + "?latitude=\(lat)&longitude=\(lon)"
            + "&hourly=temperature_2m,weather_code,wind_speed_10m"
            + "&daily=sunrise,sunset,temperature_2m_max,temperature_2m_min,weather_code"
            + "&temperature_unit=fahrenheit"
            + "&wind_speed_unit=mph"
            + "&forecast_days=2"
            + "&timezone=auto"

        guard let url = URL(string: urlString) else {
            throw WeatherError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        return try parseResponse(json)
    }

    private func parseResponse(_ json: [String: Any]) throws -> WeatherData {
        guard let hourlyData = json["hourly"] as? [String: Any],
              let dailyData = json["daily"] as? [String: Any],
              let times = hourlyData["time"] as? [String],
              let temps = hourlyData["temperature_2m"] as? [Double],
              let codes = hourlyData["weather_code"] as? [Int],
              let winds = hourlyData["wind_speed_10m"] as? [Double],
              let sunrises = dailyData["sunrise"] as? [String],
              let sunsets = dailyData["sunset"] as? [String],
              let hiTemps = dailyData["temperature_2m_max"] as? [Double],
              let loTemps = dailyData["temperature_2m_min"] as? [Double]
        else {
            throw WeatherError.parseError
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]

        let sunrise = iso.date(from: sunrises[0]) ?? Date()
        let sunset = iso.date(from: sunsets[0]) ?? Date()

        // Parse hourly forecasts
        var hourly: [HourForecast] = []
        let cal = Calendar.current
        for i in 0..<min(times.count, temps.count, codes.count) {
            guard let time = iso.date(from: times[i]) else { continue }
            hourly.append(HourForecast(
                hour: cal.component(.hour, from: time),
                temp: temps[i],
                code: codes[i],
                time: time
            ))
        }

        // Current conditions = nearest hour
        let now = Date()
        let currentIdx = hourly.enumerated().min(by: {
            abs($0.element.time.timeIntervalSince(now)) < abs($1.element.time.timeIntervalSince(now))
        })?.offset ?? 0

        let currentTemp = currentIdx < temps.count ? temps[currentIdx] : 0
        let currentCode = currentIdx < codes.count ? codes[currentIdx] : 0
        let currentWind = currentIdx < winds.count ? winds[currentIdx] : 0

        return WeatherData(
            temp: currentTemp,
            code: currentCode,
            wind: currentWind,
            hi: hiTemps.first ?? 0,
            lo: loTemps.first ?? 0,
            desc: weatherDescription(for: currentCode),
            sunrise: sunrise,
            sunset: sunset,
            hourly: hourly,
            moonPhase: Self.moonPhase(for: now),
            fetchedAt: now
        )
    }

    // MARK: - Moon Phase (synodic calculation)

    static func moonPhase(for date: Date) -> MoonPhase {
        // Known new moon: Jan 6, 2000 18:14 UTC
        let knownNew = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "UTC"),
            year: 2000, month: 1, day: 6, hour: 18, minute: 14
        ).date ?? Date.distantPast

        let synodicMonth = 29.53059
        let daysSince = date.timeIntervalSince(knownNew) / 86400.0
        let phase = ((daysSince.truncatingRemainder(dividingBy: synodicMonth)) + synodicMonth)
            .truncatingRemainder(dividingBy: synodicMonth)
        let illumination = (1.0 - cos(2.0 * .pi * phase / synodicMonth)) / 2.0
        let isWaxing = phase < synodicMonth / 2.0

        let emoji: String = {
            let eighth = synodicMonth / 8.0
            switch phase {
            case 0..<eighth:               return "🌑"
            case eighth..<(2 * eighth):    return "🌒"
            case (2*eighth)..<(3*eighth):  return "🌓"
            case (3*eighth)..<(4*eighth):  return "🌔"
            case (4*eighth)..<(5*eighth):  return "🌕"
            case (5*eighth)..<(6*eighth):  return "🌖"
            case (6*eighth)..<(7*eighth):  return "🌗"
            default:                       return "🌘"
            }
        }()

        return MoonPhase(age: phase, illumination: illumination, isWaxing: isWaxing, emoji: emoji)
    }

    // MARK: - Weather Code Descriptions

    static func weatherDescription(for code: Int) -> String {
        switch code {
        case 0:           return "Clear"
        case 1:           return "Mostly Clear"
        case 2:           return "Partly Cloudy"
        case 3:           return "Overcast"
        case 45, 48:      return "Fog"
        case 51, 53, 55:  return "Drizzle"
        case 56, 57:      return "Freezing Drizzle"
        case 61, 63, 65:  return "Rain"
        case 66, 67:      return "Freezing Rain"
        case 71, 73, 75:  return "Snow"
        case 77:          return "Snow Grains"
        case 80, 81, 82:  return "Showers"
        case 85, 86:      return "Snow Showers"
        case 95:          return "Thunderstorm"
        case 96, 99:      return "Thunderstorm w/ Hail"
        default:          return "Unknown"
        }
    }

    private func weatherDescription(for code: Int) -> String {
        Self.weatherDescription(for: code)
    }

    // MARK: - Weather Condition Symbol (SF Symbol name)

    static func conditionSymbol(for code: Int) -> String {
        switch code {
        case 0:           return "sun.max.fill"
        case 1:           return "sun.min.fill"
        case 2:           return "cloud.sun.fill"
        case 3:           return "cloud.fill"
        case 45, 48:      return "cloud.fog.fill"
        case 51, 53, 55:  return "cloud.drizzle.fill"
        case 56, 57:      return "cloud.sleet.fill"
        case 61, 63, 65:  return "cloud.rain.fill"
        case 66, 67:      return "cloud.sleet.fill"
        case 71, 73, 75:  return "snowflake"
        case 77:          return "snowflake"
        case 80, 81, 82:  return "cloud.heavyrain.fill"
        case 85, 86:      return "cloud.snow.fill"
        case 95:          return "cloud.bolt.fill"
        case 96, 99:      return "cloud.bolt.rain.fill"
        default:          return "cloud.fill"
        }
    }

    // MARK: - Weather Condition Color

    static func conditionColor(for code: Int) -> (r: Double, g: Double, b: Double) {
        switch code {
        case 0, 1:          return (1.0, 0.72, 0.30)   // golden sun
        case 2:             return (0.95, 0.78, 0.35)   // sun with cloud
        case 3:             return (0.65, 0.68, 0.72)   // overcast gray
        case 45, 48:        return (0.60, 0.63, 0.70)   // fog
        case 51...67:       return (0.35, 0.55, 0.85)   // rain/drizzle blue
        case 71...86:       return (0.82, 0.87, 0.95)   // snow white-blue
        case 95, 96, 99:    return (0.60, 0.40, 0.80)   // thunderstorm purple
        default:            return (0.65, 0.68, 0.72)
        }
    }
}

enum WeatherError: Error {
    case invalidURL
    case parseError
}
