//
//  WeatherInfo.swift
//  Breezy
//
//  Main weather information model
//

import Foundation

struct WeatherInfo: Identifiable, Codable, Equatable {
    static func == (lhs: WeatherInfo, rhs: WeatherInfo) -> Bool {
        return lhs.location == rhs.location &&
               lhs.temperature == rhs.temperature &&
               lhs.feelsLike == rhs.feelsLike &&
               lhs.highTemp == rhs.highTemp &&
               lhs.lowTemp == rhs.lowTemp &&
               lhs.condition == rhs.condition &&
               lhs.emoji == rhs.emoji &&
               lhs.metrics == rhs.metrics
    }

    let id: UUID
    let location: LocationData
    let temperature: String
    let feelsLike: String?
    let highTemp: String?
    let lowTemp: String?
    let condition: String
    let emoji: String
    let hourlyForecast: [HourlyForecast] // Every 3 hours for display
    let allHourlyData: [HourlyForecast]? // All hours for drag interpolation
    let dailyForecast: [DailyForecast]
    let metrics: WeatherMetrics?
    let timezone: String
    let timestamp: TimeInterval

    init(
        location: LocationData,
        temperature: String,
        feelsLike: String?,
        highTemp: String?,
        lowTemp: String?,
        condition: String,
        emoji: String,
        hourlyForecast: [HourlyForecast] = [],
        allHourlyData: [HourlyForecast]? = nil,
        dailyForecast: [DailyForecast] = [],
        metrics: WeatherMetrics? = nil,
        timezone: String = TimeZone.current.identifier
    ) {
        self.id = UUID()
        self.location = location
        self.temperature = temperature
        self.feelsLike = feelsLike
        self.highTemp = highTemp
        self.lowTemp = lowTemp
        self.condition = condition
        self.emoji = emoji
        self.hourlyForecast = hourlyForecast
        self.allHourlyData = allHourlyData
        self.dailyForecast = dailyForecast
        self.metrics = metrics
        self.timezone = timezone
        self.timestamp = Date().timeIntervalSince1970
    }
}

