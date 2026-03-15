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
}

