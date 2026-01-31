//
//  DailyForecast.swift
//  Breezy
//
//  Daily weather forecast model
//

import Foundation

struct DailyForecast: Identifiable, Codable, Equatable {
    var id: UUID { UUID() }
    let date: String
    let dayName: String
    let highTemp: String
    let lowTemp: String
    let condition: String
    let emoji: String
    let chanceOfRain: String?
    let windSpeed: String?
    let humidity: String?
    let sunrise: String?
    let sunset: String?
    let sunriseDate: Date? // For golden hour calculation
    let sunsetDate: Date? // For golden hour calculation
    let moonPhase: MoonPhase?
    let moonrise: String?
    let moonset: String?
    let hourlyData: [HourlyForecast]
    let allHourlyData: [HourlyForecast]? // All hours for detailed view
}

