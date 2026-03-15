//
//  HourlyForecast.swift
//  Breezy
//
//  Hourly weather forecast model
//

import Foundation

struct HourlyForecast: Identifiable, Codable, Equatable {
    let sourceDate: Date?

    var id: String {
        if let sourceDate {
            return String(Int(sourceDate.timeIntervalSince1970 * 1000))
        }
        let normalizedCondition = condition ?? "unknown"
        let normalizedWind = windSpeed ?? "calm"
        let rainChanceComponent = precipitationChance.map { String(format: "%.4f", $0) } ?? "none"
        return "\(hourValue)-\(time)-\(temperatureRaw)-\(normalizedCondition)-\(rainChanceComponent)-\(normalizedWind)"
    }

    let time: String
    let temperatureRaw: Double
    let condition: String?
    let emoji: String?
    let hourValue: Int
    let precipitationChance: Double? // 0.0 to 1.0
    let precipitationAmount: Double? // mm or inches
    let windSpeed: String?
    let windGust: Double? // wind gust speed in same unit as windSpeed
    let windDirection: String?
    let uvIndex: Int?
    let humidity: Int? // percentage 0-100
}

