//
//  AppSettings.swift
//  Breezy
//
//  App settings and preferences models
//

import SwiftUI

enum TemperatureUnit: String, CaseIterable, Identifiable, Codable {
    case celsius = "Celsius"
    case fahrenheit = "Fahrenheit"
    
    var id: String { rawValue }
    var symbol: String { self == .celsius ? "C" : "F" }
}

enum WindSpeedUnit: String, CaseIterable, Identifiable, Codable {
    case metersPerSecond = "m/s"
    case kilometersPerHour = "km/h"
    case milesPerHour = "mph"
    case knots = "Knots"
    
    var id: String { rawValue }
    var displayName: String { rawValue }
    var symbol: String { rawValue }
    
    // Convert from m/s (API default)
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
    var symbol: String { rawValue }
    
    // Convert from hPa (API default)
    func convert(_ value: Double) -> Double {
        switch self {
        case .hectopascals: return value
        case .inchesOfMercury: return value * 0.02953
        case .millimetersOfMercury: return value * 0.750062
        case .millibars: return value // same as hPa
        }
    }
}

enum VisibilityUnit: String, CaseIterable, Identifiable, Codable {
    case kilometers = "Kilometers"
    case miles = "Miles"
    
    var id: String { rawValue }
    var symbol: String { self == .kilometers ? "km" : "mi" }
    
    // Convert from meters (API default)
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
    
    // Convert from mm (API default)
    func convert(_ value: Double) -> Double {
        switch self {
        case .millimeters: return value
        case .inches: return value * 0.0393701
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case light = "Light"
    case dark = "Dark"
    case auto = "Auto"
    
    var id: String { rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .auto: return nil
        }
    }
}

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
    case sunrise = "Sunrise"
    
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
        case .sunrise: return "sunrise.fill"
        }
    }
    
    var emoji: String {
        switch self {
        case .humidity: return "💧"
        case .pressure: return "⏲"
        case .visibility: return "👁"
        case .dewPoint: return "🌡"
        case .uvIndex: return "☀️"
        case .wind: return "💨"
        case .rain: return "🌧"
        case .cloudCover: return "☁️"
        case .feelsLike: return "🌡"
        case .sunset: return "🌇"
        case .sunrise: return "🌅"
        }
    }
}

enum DateFormat: String, CaseIterable, Identifiable, Codable {
    case short = "Short"         // 1/31
    case medium = "Medium"        // Jan 31
    case long = "Long"            // January 31
    case full = "Full"            // Friday, January 31
    case iso = "ISO"              // 2026-01-31
    
    var id: String { rawValue }
    
    func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        switch self {
        case .short:
            formatter.dateFormat = "M/d"
        case .medium:
            formatter.dateFormat = "MMM d"
        case .long:
            formatter.dateFormat = "MMMM d"
        case .full:
            formatter.dateFormat = "EEEE, MMMM d"
        case .iso:
            formatter.dateFormat = "yyyy-MM-dd"
        }
        return formatter.string(from: date)
    }
    
    var example: String {
        let exampleDate = Date()
        return format(exampleDate)
    }
}
