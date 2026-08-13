//
//  WidgetWeatherData.swift
//  Breezy
//
//  Widget data model for sharing weather data with widget extension
//

import Foundation

struct WidgetWeatherData: Codable {
    let city: String
    let temperature: String
    let condition: String
    let emoji: String
    let highTemp: String?
    let lowTemp: String?
    let hourlyForecast: [WidgetHourlyForecast]
    let timestamp: Date
    let useMinimalistIcons: Bool?
    let uvIndex: Int?
    let pressure: String?
    let windSpeed: String?
    let rainChance: String?
    let rainAmount: String?
    let latitude: Double?
    let longitude: Double?
    
    // New fields for accuracy
    let conditionCode: String?
    let isDaylight: Bool?
    let minTemp: String?
    let maxTemp: String?
    let humidity: String?
    let visibility: String?
    let dailyForecast: [WidgetDailyForecast]
    
    // Additional fields for widget extension
    let sunrise: Date?
    let sunset: Date?
    let moonPhase: String?
    let moonIllumination: Double?
    let windDirectionDegrees: Double?

    /// Open-Meteo only. Surf conditions + pre-computed rating for the widget.
    let surf: WidgetSurfData?

    struct WidgetHourlyForecast: Codable {
        let time: String
        let temperature: String
        let emoji: String
        let condition: String?
    }

    struct WidgetDailyForecast: Codable {
        let dayName: String
        let highTemp: String
        let lowTemp: String
        let condition: String
    }

    /// Pre-formatted surf snapshot for widgets. Values are display-ready strings
    /// so the widget does not need to replicate the rating engine or unit math.
    struct WidgetSurfData: Codable, Equatable {
        let ratingLabel: String        // e.g. "Good"
        let ratingDetail: String       // e.g. "Chest-high waves, offshore winds, clean."
        let ratingColorHex: String     // e.g. "#5BB381"
        let waveHeight: String?        // e.g. "1.2 m"
        let wavePeriod: String?        // e.g. "8 s"
        let swellHeight: String?       // e.g. "0.9 m"
        let seaTemp: String?           // e.g. "16°C"
        let wind: String?              // e.g. "SW 6 mph"
    }
}

