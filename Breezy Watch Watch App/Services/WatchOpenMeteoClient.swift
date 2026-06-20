//
//  WatchOpenMeteoClient.swift
//  Breezy Watch Watch App
//
//  Lightweight Open-Meteo client used by the watch app and watch widgets.
//

import Foundation
import CoreLocation

final class WatchOpenMeteoClient {
    static let shared = WatchOpenMeteoClient()

    private let session: URLSession

    private init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchWeather(
        latitude: Double,
        longitude: Double,
        city: String,
        units: (temperature: WatchTemperatureUnit, wind: WindSpeedUnit, pressure: PressureUnit, visibility: VisibilityUnit)
    ) async throws -> WatchWeatherData {
        let response = try await fetchForecast(latitude: latitude, longitude: longitude)
        let timezone = TimeZone(identifier: response.timezone) ?? .current
        let hourly = makeHourly(from: response.hourly, timezone: timezone, temperatureUnit: units.temperature)
        let daily = makeDaily(from: response.daily, timezone: timezone, temperatureUnit: units.temperature, windUnit: units.wind)
        let condition = WatchOpenMeteoCondition.description(from: response.current.weatherCode)
        let currentTimestamp = parseTimestamp(response.current.time, timezone: timezone) ?? Date()

        let currentTemp = formattedTemperature(response.current.temperature2M, unit: units.temperature)
        let feelsLike = formattedTemperature(response.current.apparentTemperature, unit: units.temperature)
        let visibility = formatVisibility(response.current.visibility, unit: units.visibility)
        let pressure = formatPressure(response.current.pressureMSL, unit: units.pressure)
        let windSpeed = formatWindSpeed(kilometersPerHour: response.current.windSpeed10M, unit: units.wind)
        let humidity = response.current.relativeHumidity2M.map { Int(round($0)) }
        let cloudCover = response.current.cloudCover.map { String(format: "%.0f%%", $0) }
        let rainChance = daily.first?.precipitationChance
        let today = daily.first

        return WatchWeatherData(
            city: city,
            temperature: currentTemp,
            feelsLike: feelsLike,
            condition: condition,
            emoji: WatchWeatherIconHelper.emoji(for: condition),
            iconName: WatchWeatherIconHelper.minimalistIcon(for: condition),
            highTemp: today?.highTemp,
            lowTemp: today?.lowTemp,
            hourlyForecast: Array(hourly.prefix(24)).map {
                WatchHourlyForecast(
                    date: $0.date,
                    time: $0.time,
                    temperature: $0.temperature,
                    emoji: $0.emoji,
                    iconName: $0.iconName,
                    condition: $0.condition
                )
            },
            dailyForecast: daily,
            windSpeed: windSpeed,
            windDirection: response.current.windDirection10M.map(WatchWindDirectionHelper.cardinalDirection),
            windDirectionDegrees: response.current.windDirection10M,
            uvIndex: hourly.first(where: { Calendar.current.isDate($0.date, equalTo: currentTimestamp, toGranularity: .hour) })?.uvValue,
            rainChance: rainChance,
            humidity: humidity,
            pressure: pressure,
            visibility: visibility,
            dewPoint: nil,
            cloudCover: cloudCover,
            sunrise: today?.sunrise,
            sunset: today?.sunset,
            metadata: WatchWeatherMetadata(
                source: .openMeteo,
                fetchedAt: Date(),
                isStale: false,
                latitude: latitude,
                longitude: longitude
            )
        )
    }

    func fetchHistoricalDay(
        latitude: Double,
        longitude: Double,
        date: Date,
        temperatureUnit: WatchTemperatureUnit,
        windUnit: WindSpeedUnit
    ) async throws -> WatchHistoricalDay {
        let response = try await fetchArchive(latitude: latitude, longitude: longitude, startDate: date, endDate: date)
        let timezone = TimeZone(identifier: response.timezone) ?? .current
        let daily = makeDaily(from: response.daily, timezone: timezone, temperatureUnit: temperatureUnit, windUnit: windUnit)
        let hourly = makeHourly(from: response.hourly, timezone: timezone, temperatureUnit: temperatureUnit)

        guard let day = daily.first else {
            throw NSError(domain: "WatchOpenMeteo", code: 404, userInfo: [NSLocalizedDescriptionKey: "No data"])
        }

        let hourlyTemps = hourly.enumerated().map { index, hour in
            WatchTempPoint(index: index, temp: hour.temperatureValue)
        }

        return WatchHistoricalDay(
            date: date,
            condition: day.condition,
            emoji: day.emoji,
            iconName: day.iconName,
            highTemp: day.highTemp,
            lowTemp: day.lowTemp,
            precipChance: day.precipitationChance,
            maxWind: day.maxWindSpeed,
            hourlyTemps: hourlyTemps
        )
    }

    private func fetchForecast(latitude: Double, longitude: Double) async throws -> ForecastResponse {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,pressure_msl,cloud_cover,wind_speed_10m,wind_direction_10m,visibility"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code,uv_index"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max,wind_speed_10m_max")
        ]
        return try await fetch(url: components?.url)
    }

    private func fetchArchive(latitude: Double, longitude: Double, startDate: Date, endDate: Date) async throws -> ArchiveResponse {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        var components = URLComponents(string: "https://archive-api.open-meteo.com/v1/archive")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "start_date", value: formatter.string(from: startDate)),
            URLQueryItem(name: "end_date", value: formatter.string(from: endDate)),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,uv_index"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max,wind_speed_10m_max")
        ]
        return try await fetch(url: components?.url)
    }

    private func fetch<T: Decodable>(url: URL?) async throws -> T {
        guard let url else {
            throw NSError(domain: "WatchOpenMeteo", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(domain: "WatchOpenMeteo", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Open-Meteo returned an error"])
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    private func makeHourly(from block: HourlyBlock, timezone: TimeZone, temperatureUnit: WatchTemperatureUnit) -> [OpenMeteoWatchHourly] {
        let dates = block.time.compactMap { parseTimestamp($0, timezone: timezone) }
        return dates.enumerated().map { index, date in
            let condition = WatchOpenMeteoCondition.description(from: block.weatherCode[safe: index] ?? 0)
            let temperatureC = block.temperature2M[safe: index] ?? 0
            return OpenMeteoWatchHourly(
                date: date,
                time: WatchDateFormatterHelper.formatHour(Calendar.current.component(.hour, from: date)),
                temperatureValue: convertTemperature(temperatureC, unit: temperatureUnit),
                temperature: formattedTemperature(temperatureC, unit: temperatureUnit),
                condition: condition,
                emoji: WatchWeatherIconHelper.emoji(for: condition),
                iconName: WatchWeatherIconHelper.minimalistIcon(for: condition),
                uvValue: block.uvIndex?[safe: index].map { Int(round($0)) },
                rainChance: block.precipitationProbability?[safe: index].map { String(format: "%.0f%%", $0) }
            )
        }
    }

    private func makeDaily(from block: DailyBlock, timezone: TimeZone, temperatureUnit: WatchTemperatureUnit, windUnit: WindSpeedUnit) -> [WatchDailyForecast] {
        let dates = block.time.compactMap { parseDate($0, timezone: timezone) }
        let sunrise = block.sunrise.compactMap { parseTimestamp($0, timezone: timezone) }
        let sunset = block.sunset.compactMap { parseTimestamp($0, timezone: timezone) }
        var forecasts: [WatchDailyForecast] = []
        forecasts.reserveCapacity(dates.count)

        for (index, date) in dates.enumerated() {
            let condition = WatchOpenMeteoCondition.description(from: block.weatherCode[safe: index] ?? 0)
            let lowC = block.temperature2MMin[safe: index] ?? 0
            let highC = block.temperature2MMax[safe: index] ?? 0
            let lowValue = convertTemperature(lowC, unit: temperatureUnit)
            let highValue = convertTemperature(highC, unit: temperatureUnit)

            forecasts.append(WatchDailyForecast(
                dayName: Calendar.current.isDateInToday(date) ? "Today" : shortWeekday(for: date),
                iconName: WatchWeatherIconHelper.minimalistIcon(for: condition),
                emoji: WatchWeatherIconHelper.emoji(for: condition),
                lowTemp: String(format: "%.0f°", lowValue),
                highTemp: String(format: "%.0f°", highValue),
                lowValue: lowValue,
                highValue: highValue,
                condition: condition,
                precipitationChance: block.precipitationProbabilityMax?[safe: index].map { String(format: "%.0f%%", $0) } ?? "0%",
                maxWindSpeed: formatWindSpeed(kilometersPerHour: block.windSpeed10MMax?[safe: index], unit: windUnit) ?? "0 \(windUnit.displayName)",
                uvIndex: "0",
                sunrise: sunrise[safe: index].map(WatchDateFormatterHelper.formatTime),
                sunset: sunset[safe: index].map(WatchDateFormatterHelper.formatTime),
                hourlyForecast: []
            ))
        }

        return forecasts
    }

    private func formattedTemperature(_ celsius: Double, unit: WatchTemperatureUnit) -> String {
        String(format: "%.0f°%@", convertTemperature(celsius, unit: unit), unit.symbol)
    }

    private func convertTemperature(_ celsius: Double, unit: WatchTemperatureUnit) -> Double {
        unit == .fahrenheit ? ((celsius * 9.0 / 5.0) + 32.0) : celsius
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

    private func shortWeekday(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
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
}

private struct OpenMeteoWatchHourly {
    let date: Date
    let time: String
    let temperatureValue: Double
    let temperature: String
    let condition: String
    let emoji: String
    let iconName: String
    let uvValue: Int?
    let rainChance: String?
}

private enum WatchOpenMeteoCondition {
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

private struct ArchiveResponse: Decodable {
    let timezone: String
    let hourly: HourlyBlock
    let daily: DailyBlock
}

private struct CurrentBlock: Decodable {
    let time: String
    let temperature2M: Double
    let relativeHumidity2M: Double?
    let apparentTemperature: Double
    let precipitation: Double?
    let weatherCode: Int
    let pressureMSL: Double?
    let cloudCover: Double?
    let windSpeed10M: Double
    let windDirection10M: Double?
    let visibility: Double?

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2M = "temperature_2m"
        case relativeHumidity2M = "relative_humidity_2m"
        case apparentTemperature = "apparent_temperature"
        case precipitation
        case weatherCode = "weather_code"
        case pressureMSL = "pressure_msl"
        case cloudCover = "cloud_cover"
        case windSpeed10M = "wind_speed_10m"
        case windDirection10M = "wind_direction_10m"
        case visibility
    }
}

private struct HourlyBlock: Decodable {
    let time: [String]
    let temperature2M: [Double]
    let precipitationProbability: [Double]?
    let weatherCode: [Int]
    let uvIndex: [Double]?

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2M = "temperature_2m"
        case precipitationProbability = "precipitation_probability"
        case weatherCode = "weather_code"
        case uvIndex = "uv_index"
    }
}

private struct DailyBlock: Decodable {
    let time: [String]
    let weatherCode: [Int]
    let temperature2MMax: [Double]
    let temperature2MMin: [Double]
    let sunrise: [String]
    let sunset: [String]
    let precipitationProbabilityMax: [Double]?
    let windSpeed10MMax: [Double]?

    enum CodingKeys: String, CodingKey {
        case time
        case weatherCode = "weather_code"
        case temperature2MMax = "temperature_2m_max"
        case temperature2MMin = "temperature_2m_min"
        case sunrise
        case sunset
        case precipitationProbabilityMax = "precipitation_probability_max"
        case windSpeed10MMax = "wind_speed_10m_max"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
