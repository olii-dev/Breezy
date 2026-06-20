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
            dailyForecast: daily.prefix(10).map {
                WidgetWeatherData.WidgetDailyForecast(
                    dayName: $0.dayName,
                    highTemp: $0.highTemp,
                    lowTemp: $0.lowTemp,
                    condition: $0.condition
                )
            }
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
            URLQueryItem(name: "forecast_days", value: "10")
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
