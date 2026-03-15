//
//  WatchSharedModels.swift
//  Breezy Watch Watch App
//
//  Shared enums and weather models for Watch surfaces.
//

import Foundation
import SwiftUI

enum WeatherFont: String, CaseIterable, Identifiable, Codable {
    case system = "System"
    case rounded = "Rounded"
    case serif = "Serif"
    case mono = "Monospace"
    
    var id: String { rawValue }
    
    var design: Font.Design {
        switch self {
        case .system: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .mono: return .monospaced
        }
    }
}

enum WeatherMetric: String, CaseIterable, Identifiable, Codable {
    case humidity = "Humidity"
    case pressure = "Pressure"
    case visibility = "Visibility"
    case dewPoint = "Dew Point"
    case uvIndex = "UV Index"
    case wind = "Wind"
    case rain = "Rain Chance"
    case cloudCover = "Cloud Cover"
    case feelsLike = "Feels Like"
    case sunset = "Sunset"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .humidity: return "humidity"
        case .pressure: return "gauge.medium"
        case .visibility: return "eye.fill"
        case .dewPoint: return "drop.degreesign"
        case .uvIndex: return "sun.max.fill"
        case .wind: return "wind"
        case .rain: return "cloud.rain.fill"
        case .cloudCover: return "cloud.fill"
        case .feelsLike: return "thermometer.medium"
        case .sunset: return "sunset.fill"
        }
    }
    
    var emoji: String {
        switch self {
        case .humidity: return "💧" // Not sf symbol
        case .pressure: return "⏲"
        case .visibility: return "👁"
        case .dewPoint: return "🌡"
        case .uvIndex: return "☀️"
        case .wind: return "💨"
        case .rain: return "🌧"
        case .cloudCover: return "☁️"
        case .feelsLike: return "🌡"
        case .sunset: return "🌇"
        }
    }
}

// MARK: - Unit Types (shared with iOS)

enum WindSpeedUnit: String, CaseIterable, Identifiable, Codable {
    case metersPerSecond = "m/s"
    case kilometersPerHour = "km/h"
    case milesPerHour = "mph"
    case knots = "Knots"
    
    var id: String { rawValue }
    var displayName: String { rawValue }
    
    func convert(_ value: Double) -> Double {
        switch self {
        case .metersPerSecond: return value
        case .kilometersPerHour: return value * 3.6
        case .milesPerHour: return value * 2.23694
        case .knots: return value * 1.94384
        }
    }
}

enum PressureUnit: String, CaseIterable, Identifiable, Codable {
    case hectopascals = "hPa"
    case inchesOfMercury = "inHg"
    case millimetersOfMercury = "mmHg"
    case millibars = "mbar"
    
    var id: String { rawValue }
    var displayName: String { rawValue }
    
    func convert(_ value: Double) -> Double {
        switch self {
        case .hectopascals: return value
        case .inchesOfMercury: return value * 0.02953
        case .millimetersOfMercury: return value * 0.750062
        case .millibars: return value
        }
    }
}

enum VisibilityUnit: String, CaseIterable, Identifiable, Codable {
    case kilometers = "Kilometers"
    case miles = "Miles"
    
    var id: String { rawValue }
    var symbol: String { self == .kilometers ? "km" : "mi" }
    
    func convert(_ value: Double) -> Double {
        switch self {
        case .kilometers: return value / 1000
        case .miles: return value / 1609.34
        }
    }
}

enum PrecipitationUnit: String, CaseIterable, Identifiable, Codable {
    case millimeters = "Millimeters"
    case inches = "Inches"
    
    var id: String { rawValue }
    var symbol: String { self == .millimeters ? "mm" : "in" }
    
    func convert(_ value: Double) -> Double {
        switch self {
        case .millimeters: return value
        case .inches: return value * 0.0393701
        }
    }
}

enum WatchWeatherDataSource: String, Codable {
    case phone
    case weatherKit
    case cache
}

struct WatchWeatherMetadata {
    let source: WatchWeatherDataSource
    let fetchedAt: Date
    let isStale: Bool
    let latitude: Double?
    let longitude: Double?
}

struct WatchWeatherData {
    let city: String
    let temperature: String
    let feelsLike: String?
    let condition: String
    let emoji: String
    let iconName: String
    let highTemp: String?
    let lowTemp: String?
    let hourlyForecast: [WatchHourlyForecast]
    let dailyForecast: [WatchDailyForecast]
    let windSpeed: String?
    let windDirection: String?
    let windDirectionDegrees: Double?
    let uvIndex: Int?
    let rainChance: String?
    let humidity: Int?
    let pressure: String?
    let visibility: String?
    let dewPoint: String?
    let cloudCover: String?
    let sunrise: String?
    let sunset: String?
    let metadata: WatchWeatherMetadata
}

struct WatchHourlyForecast: Identifiable {
    var id: Date { date }

    let date: Date
    let time: String
    let temperature: String
    let emoji: String
    let iconName: String
    let condition: String
}

struct WatchDailyForecast: Identifiable {
    let id = UUID()
    let dayName: String
    let iconName: String
    let emoji: String
    let lowTemp: String
    let highTemp: String
    let lowValue: Double
    let highValue: Double
    let condition: String
    let precipitationChance: String
    let maxWindSpeed: String
    let uvIndex: String
    let sunrise: String?
    let sunset: String?
    let hourlyForecast: [WatchHourlyForecast]
}

enum WatchAppStorageKey {
    static let appGroup = "group.com.breezy.weather"
    static let temperatureUnit = "Breezy.temperatureUnit"
    static let selectedLocationID = "WatchSelectedLocationID"
    static let savedLocations = "WatchSavedLocations"
    static let lastLatitude = "WatchLastLatitude"
    static let lastLongitude = "WatchLastLongitude"
    static let lastCity = "WatchLastCity"
    static let lastTemperature = "WatchLastTemperature"
    static let lastCondition = "WatchLastCondition"
    static let lastEmoji = "WatchLastEmoji"
    static let lastHighTemp = "WatchLastHighTemp"
    static let lastLowTemp = "WatchLastLowTemp"
    static let lastCacheTimestamp = "WatchLastCacheTimestamp"
    static let windSpeedUnit = "Breezy.windSpeedUnit"
    static let pressureUnit = "Breezy.pressureUnit"
    static let visibilityUnit = "Breezy.visibilityUnit"
    static let shouldFollowGPS = "Breezy.shouldFollowGPS"
    static let showMainHighlights = "WatchShowMainHighlights"
    static let showMainSunSchedule = "WatchShowMainSunSchedule"
    static let showRefreshStatus = "WatchShowRefreshStatus"
    static let showDayMetrics = "WatchShowDayMetrics"
    static let showDaySunSchedule = "WatchShowDaySunSchedule"
    static let showDayHourlyChart = "WatchShowDayHourlyChart"
    static let showDayHourlyForecast = "WatchShowDayHourlyForecast"
}
