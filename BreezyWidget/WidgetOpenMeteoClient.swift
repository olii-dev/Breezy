//
//  WidgetOpenMeteoClient.swift
//  BreezyWidget
//
//  Lightweight Open-Meteo fetcher for source-aware widget refreshes.
//

import Foundation
import CoreLocation

final class WidgetOpenMeteoClient {
    static let shared = WidgetOpenMeteoClient()

    private let session: URLSession

    private init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchWeather(
        latitude: Double,
        longitude: Double,
        cachedCity: String?,
        defaults: UserDefaults?
    ) async throws -> WidgetWeatherData {
        let response = try await fetchForecast(latitude: latitude, longitude: longitude)
        let timezone = TimeZone(identifier: response.timezone) ?? .current
        let city = try await resolveCity(latitude: latitude, longitude: longitude, fallback: cachedCity)

        let isFahrenheit = (defaults?.string(forKey: "Breezy.temperatureUnit") ?? "") == "Fahrenheit"
        let windUnit = WindSpeedUnit(rawValue: defaults?.string(forKey: "Breezy.windSpeedUnit") ?? "") ?? .metersPerSecond
        let precipitationUnit = PrecipitationUnit(rawValue: defaults?.string(forKey: "Breezy.precipitationUnit") ?? "") ?? .millimeters
        let visibilityUnit = VisibilityUnit(rawValue: defaults?.string(forKey: "Breezy.visibilityUnit") ?? "") ?? .kilometers
        let pressureUnit = PressureUnit(rawValue: defaults?.string(forKey: "Breezy.pressureUnit") ?? "") ?? .hectopascals
        let useMinimalistIcons = defaults?.object(forKey: "Breezy.useMinimalistIcons") as? Bool ?? true

        let hourly = makeHourly(from: response.hourly, timezone: timezone, isFahrenheit: isFahrenheit)
        let daily = makeDaily(from: response.daily, timezone: timezone, isFahrenheit: isFahrenheit)
        let condition = WidgetOpenMeteoCondition.description(from: response.current.weatherCode)
        let currentDate = parseTimestamp(response.current.time, timezone: timezone) ?? Date()
        let currentHour = hourly.first(where: { Calendar.current.isDate($0.date, equalTo: currentDate, toGranularity: .hour) })

        let todayRainChance = daily.first?.rainChance ?? "0%"
        let todayRainAmount = daily.first?.precipitationSumMillimeters ?? 0

        // Marine data (non-fatal — inland locations return no marine block).
        // Surf is Open-Meteo only; WeatherKit path never reaches this client.
        let marineResponse = try? await fetchMarine(latitude: latitude, longitude: longitude)
        let surf = makeSurfData(
            from: marineResponse?.current,
            windSpeedKmh: response.current.windSpeed10M,
            windDirectionDegrees: response.current.windDirection10M,
            isFahrenheit: isFahrenheit,
            windUnit: windUnit
        )

        return WidgetWeatherData(
            city: city,
            temperature: formatTemperature(response.current.temperature2M, isFahrenheit: isFahrenheit),
            condition: condition,
            emoji: WidgetIconHelper.getIcon(for: condition, isMinimalist: false),
            highTemp: daily.first?.highTemp,
            lowTemp: daily.first?.lowTemp,
            hourlyForecast: hourly.prefix(12).map {
                WidgetWeatherData.WidgetHourlyForecast(
                    time: $0.time,
                    temperature: $0.temperature,
                    emoji: $0.emoji,
                    condition: $0.condition
                )
            },
            timestamp: Date(),
            useMinimalistIcons: useMinimalistIcons,
            uvIndex: currentHour?.uvIndex,
            pressure: formatPressure(response.current.pressureMSL, unit: pressureUnit),
            windSpeed: formatWindSpeed(kilometersPerHour: response.current.windSpeed10M, unit: windUnit),
            rainChance: todayRainChance,
            rainAmount: String(format: "%.1f %@", precipitationUnit.convert(todayRainAmount), precipitationUnit.symbol),
            latitude: latitude,
            longitude: longitude,
            conditionCode: String(response.current.weatherCode),
            isDaylight: nil,
            minTemp: daily.first?.lowTemp,
            maxTemp: daily.first?.highTemp,
            humidity: response.current.relativeHumidity2M.map { String(format: "%.0f%%", $0) },
            visibility: formatVisibility(response.current.visibility, unit: visibilityUnit),
            sunrise: daily.first?.sunriseDate,
            sunset: daily.first?.sunsetDate,
            moonPhase: nil,
            moonIllumination: nil,
            windDirectionDegrees: response.current.windDirection10M,
            dailyForecast: daily.prefix(14).map {
                WidgetWeatherData.WidgetDailyForecast(
                    dayName: $0.dayName,
                    highTemp: $0.highTemp,
                    lowTemp: $0.lowTemp,
                    condition: $0.condition
                )
            },
            surf: surf
        )
    }

    private func fetchForecast(latitude: Double, longitude: Double) async throws -> ForecastResponse {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,weather_code,pressure_msl,wind_speed_10m,wind_direction_10m,visibility"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,uv_index"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,sunrise,sunset"),
            URLQueryItem(name: "forecast_days", value: "14")
        ]

        guard let url = components?.url else {
            throw NSError(domain: "WidgetOpenMeteo", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(domain: "WidgetOpenMeteo", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Open-Meteo returned an error"])
        }

        return try JSONDecoder().decode(ForecastResponse.self, from: data)
    }

    private func resolveCity(latitude: Double, longitude: Double, fallback: String?) async throws -> String {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first,
           let locality = placemark.locality,
           !locality.isEmpty {
            return locality
        }
        return fallback ?? "My Location"
    }

    private func makeHourly(from block: HourlyBlock, timezone: TimeZone, isFahrenheit: Bool) -> [OpenMeteoWidgetHour] {
        block.time.enumerated().compactMap { index, raw in
            guard let date = parseTimestamp(raw, timezone: timezone) else { return nil }
            let condition = WidgetOpenMeteoCondition.description(from: block.weatherCode[safe: index] ?? 0)
            let icon = WidgetIconHelper.getIcon(for: condition, isMinimalist: false)
            return OpenMeteoWidgetHour(
                date: date,
                time: hourString(for: date),
                temperature: formatTemperature(block.temperature2M[safe: index] ?? 0, isFahrenheit: isFahrenheit),
                condition: condition,
                emoji: icon,
                uvIndex: block.uvIndex?[safe: index].map { Int(round($0)) }
            )
        }
    }

    private func makeDaily(from block: DailyBlock, timezone: TimeZone, isFahrenheit: Bool) -> [OpenMeteoWidgetDay] {
        var days: [OpenMeteoWidgetDay] = []
        for (index, raw) in block.time.enumerated() {
            guard let date = parseDate(raw, timezone: timezone) else { continue }
            let condition = WidgetOpenMeteoCondition.description(from: block.weatherCode[safe: index] ?? 0)
            days.append(OpenMeteoWidgetDay(
                dayName: dayName(for: date),
                highTemp: formatTemperature(block.temperature2MMax[safe: index] ?? 0, isFahrenheit: isFahrenheit),
                lowTemp: formatTemperature(block.temperature2MMin[safe: index] ?? 0, isFahrenheit: isFahrenheit),
                condition: condition,
                rainChance: block.precipitationProbabilityMax?[safe: index].map { String(format: "%.0f%%", $0) } ?? "0%",
                precipitationSumMillimeters: block.precipitationSum?[safe: index] ?? 0,
                sunriseDate: block.sunrise[safe: index].flatMap { parseTimestamp($0, timezone: timezone) },
                sunsetDate: block.sunset[safe: index].flatMap { parseTimestamp($0, timezone: timezone) }
            ))
        }
        return days
    }

    private func formatTemperature(_ celsius: Double, isFahrenheit: Bool) -> String {
        let value = isFahrenheit ? ((celsius * 9.0 / 5.0) + 32.0) : celsius
        return String(format: "%.0f°", value)
    }

    private func formatWindSpeed(kilometersPerHour: Double?, unit: WindSpeedUnit) -> String? {
        guard let kilometersPerHour else { return nil }
        let metersPerSecond = kilometersPerHour / 3.6
        return String(format: "%.0f %@", unit.convert(metersPerSecond), unit.displayName)
    }

    private func formatPressure(_ hectopascals: Double?, unit: PressureUnit) -> String? {
        guard let hectopascals else { return nil }
        let converted = unit.convert(hectopascals)
        switch unit {
        case .inchesOfMercury:
            return String(format: "%.2f inHg", converted)
        case .millimetersOfMercury:
            return String(format: "%.0f mmHg", converted)
        case .millibars:
            return String(format: "%.0f mbar", converted)
        case .hectopascals:
            return String(format: "%.0f hPa", converted)
        }
    }

    private func formatVisibility(_ meters: Double?, unit: VisibilityUnit) -> String? {
        guard let meters else { return nil }
        return String(format: "%.1f %@", unit.convert(meters), unit.symbol)
    }

    private func parseTimestamp(_ value: String, timezone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = timezone
        return formatter.date(from: value)
    }

    private func parseDate(_ value: String, timezone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = timezone
        return formatter.date(from: value)
    }

    private func hourString(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        if hour == 0 { return "12AM" }
        if hour < 12 { return "\(hour)AM" }
        if hour == 12 { return "12PM" }
        return "\(hour - 12)PM"
    }

    private func dayName(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    // MARK: - Marine / Surf

    private func fetchMarine(latitude: Double, longitude: Double) async throws -> MarineResponse {
        var components = URLComponents(string: "https://marine-api.open-meteo.com/v1/marine")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "current", value: "wave_height,wave_direction,wave_period,wind_wave_height,swell_wave_height,swell_wave_direction,sea_surface_temperature")
        ]

        guard let url = components?.url else {
            throw NSError(domain: "WidgetOpenMeteo.Marine", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid marine URL"])
        }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(domain: "WidgetOpenMeteo.Marine", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Marine API error"])
        }
        return try JSONDecoder().decode(MarineResponse.self, from: data)
    }

    /// Build the pre-formatted surf payload from raw marine + wind values.
    /// Mirrors the app's SurfRatingEngine (kept in sync; pure logic).
    private func makeSurfData(
        from marine: MarineCurrentBlock?,
        windSpeedKmh: Double?,
        windDirectionDegrees: Double?,
        isFahrenheit: Bool,
        windUnit: WindSpeedUnit
    ) -> WidgetWeatherData.WidgetSurfData? {
        guard let marine, marine.waveHeight != nil else { return nil }

        let windMps = windSpeedKmh.map { $0 / 3.6 }
        let rating = WidgetSurfRatingEngine.rating(
            waveHeight: marine.waveHeight,
            wavePeriod: marine.wavePeriod,
            windSpeedMps: windMps,
            windDirection: windDirectionDegrees,
            waveDirection: marine.swellWaveDirection ?? marine.waveDirection
        )

        let windString: String? = {
            guard let windMps else { return nil }
            let speed = String(format: "%.0f %@", windUnit.convert(windMps), windUnit.displayName)
            if let dir = windDirectionDegrees {
                return "\(widgetCardinal(from: dir)) \(speed)"
            }
            return speed
        }()

        let seaTemp: String? = marine.seaSurfaceTemperature.map { c in
            isFahrenheit ? String(format: "%.0f°F", (c * 9.0 / 5.0) + 32.0)
                         : String(format: "%.0f°C", c)
        }

        return WidgetWeatherData.WidgetSurfData(
            ratingLabel: rating.label,
            ratingDetail: rating.detail,
            ratingColorHex: rating.hexColor,
            waveHeight: marine.waveHeight.map { String(format: "%.1f m", $0) },
            wavePeriod: marine.wavePeriod.map { String(format: "%.0f s", $0) },
            swellHeight: (marine.swellWaveHeight ?? marine.windWaveHeight).map { String(format: "%.1f m", $0) },
            seaTemp: seaTemp,
            wind: windString
        )
    }

    private func widgetCardinal(from degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let index = Int((normalized + 22.5) / 45.0) % 8
        return directions[index]
    }
}

private struct OpenMeteoWidgetHour {
    let date: Date
    let time: String
    let temperature: String
    let condition: String
    let emoji: String
    let uvIndex: Int?
}

private struct OpenMeteoWidgetDay {
    let dayName: String
    let highTemp: String
    let lowTemp: String
    let condition: String
    let rainChance: String
    let precipitationSumMillimeters: Double
    let sunriseDate: Date?
    let sunsetDate: Date?
}

private enum WidgetOpenMeteoCondition {
    static func description(from code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Foggy"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61, 63: return "Rain"
        case 65: return "Heavy Rain"
        case 66, 67: return "Freezing Rain"
        case 71, 73: return "Snow"
        case 75: return "Heavy Snow"
        case 77: return "Flurries"
        case 80, 81: return "Sun Showers"
        case 82: return "Heavy Rain"
        case 85, 86: return "Snow"
        case 95: return "Thunderstorms"
        case 96, 99: return "Strong Storms"
        default: return "Unknown"
        }
    }
}

private struct ForecastResponse: Decodable {
    let timezone: String
    let current: CurrentBlock
    let hourly: HourlyBlock
    let daily: DailyBlock
}

private struct CurrentBlock: Decodable {
    let time: String
    let temperature2M: Double
    let relativeHumidity2M: Double?
    let weatherCode: Int
    let pressureMSL: Double?
    let windSpeed10M: Double?
    let windDirection10M: Double?
    let visibility: Double?

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2M = "temperature_2m"
        case relativeHumidity2M = "relative_humidity_2m"
        case weatherCode = "weather_code"
        case pressureMSL = "pressure_msl"
        case windSpeed10M = "wind_speed_10m"
        case windDirection10M = "wind_direction_10m"
        case visibility
    }
}

private struct HourlyBlock: Decodable {
    let time: [String]
    let temperature2M: [Double]
    let weatherCode: [Int]
    let uvIndex: [Double]?

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2M = "temperature_2m"
        case weatherCode = "weather_code"
        case uvIndex = "uv_index"
    }
}

private struct DailyBlock: Decodable {
    let time: [String]
    let weatherCode: [Int]
    let temperature2MMax: [Double]
    let temperature2MMin: [Double]
    let precipitationProbabilityMax: [Double]?
    let precipitationSum: [Double]?
    let sunrise: [String]
    let sunset: [String]

    enum CodingKeys: String, CodingKey {
        case time
        case weatherCode = "weather_code"
        case temperature2MMax = "temperature_2m_max"
        case temperature2MMin = "temperature_2m_min"
        case precipitationProbabilityMax = "precipitation_probability_max"
        case precipitationSum = "precipitation_sum"
        case sunrise
        case sunset
    }
}

// MARK: - Marine response

private struct MarineResponse: Decodable {
    let current: MarineCurrentBlock?
}

private struct MarineCurrentBlock: Decodable {
    let waveHeight: Double?
    let waveDirection: Double?
    let wavePeriod: Double?
    let windWaveHeight: Double?
    let swellWaveHeight: Double?
    let swellWaveDirection: Double?
    let seaSurfaceTemperature: Double?

    enum CodingKeys: String, CodingKey {
        case waveHeight = "wave_height"
        case waveDirection = "wave_direction"
        case wavePeriod = "wave_period"
        case windWaveHeight = "wind_wave_height"
        case swellWaveHeight = "swell_wave_height"
        case swellWaveDirection = "swell_wave_direction"
        case seaSurfaceTemperature = "sea_surface_temperature"
    }
}

// MARK: - Widget surf rating engine
// Compact port of the app's SurfRatingEngine. Kept in sync; pure logic.

private enum WidgetSurfRatingEngine {
    struct Result { let label: String; let detail: String; let hexColor: String }

    static func rating(
        waveHeight: Double?,
        wavePeriod: Double?,
        windSpeedMps: Double?,
        windDirection: Double?,
        waveDirection: Double?
    ) -> Result {
        guard let height = waveHeight, height > 0 else {
            return Result(label: "Flat", detail: "No rideable waves right now.", hexColor: "#9AA4AE")
        }

        var points = heightPoints(height)
        let pn = periodAdjust(&points, period: wavePeriod)
        let wn = windAdjust(&points, windSpeed: windSpeedMps, windDirection: windDirection, waveDirection: waveDirection)

        let r = ratingFromPoints(points)
        var parts: [String] = [heightDescription(height)]
        if let pn { parts.append(pn) }
        if let wn { parts.append(wn) }
        return Result(label: r.label, detail: parts.joined(separator: ", ") + ".", hexColor: r.hexColor)
    }

    private static func heightPoints(_ h: Double) -> Double {
        switch h {
        case ..<0.25:    return 0
        case 0.25..<0.5: return 1
        case 0.5..<0.9:  return 2.5
        case 0.9..<1.5:  return 4
        case 1.5..<2.5:  return 5
        default:         return 6
        }
    }

    private static func periodAdjust(_ p: inout Double, period: Double?) -> String? {
        guard let period else { return nil }
        switch period {
        case 11...:   p += 2; return "long-period groundswell"
        case 9..<11:  p += 1; return "decent swell period"
        case 7..<9:   return nil
        default:      p -= 1; return "short, windy swell"
        }
    }

    private static func windAdjust(_ p: inout Double, windSpeed: Double?, windDirection: Double?, waveDirection: Double?) -> String? {
        guard let windSpeed, let windDirection, let waveDirection else { return nil }
        let rel = angularDifference(windDirection, waveDirection)
        switch (rel, windSpeed) {
        case (135...225, _):
            p += 1.5; return "offshore winds, clean"
        case (45..<135, _), (225..<315, _):
            if windSpeed >= 8 { p -= 0.5; return "gusty cross-shore wind" }
            return "light cross-shore wind"
        default:
            switch windSpeed {
            case 8...:  p -= 2; return "strong onshore winds, choppy"
            case 4..<8: p -= 1; return "onshore breeze"
            default:    return "light onshore breeze"
            }
        }
    }

    private static func angularDifference(_ a: Double, _ b: Double) -> Double {
        let d = (a - b).truncatingRemainder(dividingBy: 360)
        let abs = Swift.abs(d)
        return abs > 180 ? 360 - abs : abs
    }

    private static func ratingFromPoints(_ p: Double) -> (label: String, hexColor: String) {
        switch p {
        case ..<1:    return ("Flat", "#9AA4AE")
        case ..<2.5:  return ("Poor", "#8D99AE")
        case ..<4.5:  return ("Fair", "#E2C044")
        case ..<6.5:  return ("Good", "#5BB381")
        default:      return ("Epic", "#3DA9FC")
        }
    }

    private static func heightDescription(_ m: Double) -> String {
        switch m {
        case ..<0.3:    return "Ankle-slapper waves"
        case 0.3..<0.6: return "Knee-high waves"
        case 0.6..<0.9: return "Thigh-to-waist high"
        case 0.9..<1.3: return "Chest-high waves"
        case 1.3..<1.8: return "Head-high waves"
        case 1.8..<2.5: return "Overhead waves"
        default:        return "Double-overhead+"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
