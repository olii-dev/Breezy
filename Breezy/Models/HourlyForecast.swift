//
//  HourlyForecast.swift
//  Breezy
//
//  Hourly weather forecast model
//

import Foundation

struct HourlyForecast: Identifiable, Codable, Equatable {
    var id: UUID { UUID() }
    let time: String
    let temperatureRaw: Double
    let condition: String
    let emoji: String
    let hourValue: Int
    let precipitationChance: Double? // 0.0 to 1.0
    let windSpeed: String?
    let windDirection: String?
    let uvIndex: Int?
}

