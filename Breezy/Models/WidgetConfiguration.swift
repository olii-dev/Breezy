//
//  WidgetConfiguration.swift
//  Breezy
//
//  Created for Custom Widget Builder
//

import SwiftUI
import Foundation

struct CustomWidgetConfiguration: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var backgroundStyle: WidgetBackgroundStyle
    var customColors: [CustomColor] // Strings for Codable
    var fontStyle: WidgetFontStyle
    var metrics: [WidgetMetricPosition: WidgetMetricType]
    var iconStyle: WidgetIconStyle
    var widgetSize: WidgetSize
    var layoutStyle: WidgetLayout
    var showBorder: Bool
    
    static var `default`: CustomWidgetConfiguration {
        CustomWidgetConfiguration(
            id: UUID(),
            name: "My Widget",
            backgroundStyle: .gradient,
            customColors: [],
            fontStyle: .system,
            metrics: [
                .topLeft: .uvIndex,
                .topRight: .wind,
                .bottomLeft: .humidity,
                .bottomRight: .visibility
            ],
            iconStyle: .minimalist,
            widgetSize: .small,
            layoutStyle: .standard,
            showBorder: false
        )
    }
}

// MARK: - Enums

enum WidgetSize: String, CaseIterable, Codable, Identifiable {
    case small
    case medium
    case large
    
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum WidgetLayout: String, CaseIterable, Codable, Identifiable {
    case standard // Corners + Center
    case split // Left/Right (Medium)
    case list // List of metrics
    case minimal // Just big temp/icon
    
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum WidgetBackgroundStyle: String, CaseIterable, Codable, Identifiable {
    case solid
    case gradient
    case blur
    case weatherMatch
    
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .solid: return "Solid Color"
        case .gradient: return "Gradient"
        case .blur: return "Blur Material"
        case .weatherMatch: return "Match Weather"
        }
    }
}

enum WidgetFontStyle: String, CaseIterable, Codable, Identifiable {
    case system
    case rounded
    case serif
    case monospaced
    
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    
    var design: Font.Design {
        switch self {
        case .system: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }
}

enum WidgetIconStyle: String, CaseIterable, Codable, Identifiable {
    case minimalist
    case emoji
    case realistic
    
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum WidgetMetricPosition: String, CaseIterable, Codable, Identifiable {
    case topLeft
    case topCenter // New
    case topRight
    case middleLeft // New
    case center
    case middleRight // New
    case bottomLeft
    case bottomCenter // New
    case bottomRight
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topCenter: return "Top Center"
        case .topRight: return "Top Right"
        case .middleLeft: return "Middle Left"
        case .center: return "Center"
        case .middleRight: return "Middle Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight: return "Bottom Right"
        }
    }
}

enum WidgetMetricType: String, CaseIterable, Codable, Identifiable {
    case temperature
    case condition
    case uvIndex
    case wind
    case humidity
    case visibility
    case feelsLike
    case precipChance
    case rainAmount
    case pressure
    case highLow
    case dailyForecast // New
    case aqi           // New
    case temperatureChart // New - Added for Widget Chart
    
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .temperature: return "Temperature"
        case .condition: return "Condition Text"
        case .uvIndex: return "UV Index"
        case .wind: return "Wind Speed"
        case .humidity: return "Humidity"
        case .visibility: return "Visibility"
        case .feelsLike: return "Feels Like"
        case .precipChance: return "Rain Chance"
        case .rainAmount: return "Rain Amount"
        case .pressure: return "Pressure"
        case .highLow: return "High / Low"
        case .dailyForecast: return "Daily Forecast"
        case .aqi: return "Air Quality"
        case .temperatureChart: return "Temp Chart"
        }
    }
    
    var icon: String {
        switch self {
        case .temperature: return "thermometer.medium"
        case .condition: return "cloud.sun.fill"
        case .uvIndex: return "sun.max.fill"
        case .wind: return "wind"
        case .humidity: return "humidity.fill"
        case .visibility: return "eye.fill"
        case .feelsLike: return "figure.stand"
        case .precipChance: return "umbrella.fill"
        case .rainAmount: return "drop.fill"
        case .pressure: return "barometer"
        case .highLow: return "arrow.up.arrow.down"
        case .dailyForecast: return "calendar"
        case .aqi: return "aqi.low"
        case .temperatureChart: return "chart.xyaxis.line"
        }
    }
}

// Helper struct for codable colors
struct CustomColor: Codable, Identifiable, Equatable {
    var id = UUID()
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double
    
    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
    
    init(color: Color) {
        if let components = UIColor(color).cgColor.components {
            if components.count >= 3 {
                self.red = Double(components[0])
                self.green = Double(components[1])
                self.blue = Double(components[2])
                self.opacity = components.count >= 4 ? Double(components[3]) : 1.0
            } else if components.count == 2 {
                // Grayscale
                self.red = Double(components[0])
                self.green = Double(components[0])
                self.blue = Double(components[0])
                self.opacity = Double(components[1])
            } else {
                 // Fallback
                self.red = 1
                self.green = 1
                self.blue = 1
                self.opacity = 1
            }
        } else {
            // Fallback
             self.red = 1
             self.green = 1
             self.blue = 1
             self.opacity = 1
        }
    }
    
    init(r: Double, g: Double, b: Double, a: Double = 1.0) {
        self.red = r
        self.green = g
        self.blue = b
        self.opacity = a
    }
}
