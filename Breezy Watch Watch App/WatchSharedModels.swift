//
//  WatchSharedModels.swift
//  Breezy Watch Watch App
//
//  Shared enums for Watch App
//

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
