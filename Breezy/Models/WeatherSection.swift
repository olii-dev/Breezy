//
//  WeatherSection.swift
//  Breezy
//
//  Model for reorderable weather sections
//

import Foundation

enum WidgetType: String, Codable, CaseIterable, Identifiable {
    case hourlyForecast = "Hourly Forecast"
    case dailyForecast = "Daily Forecast"
    case deepDetails = "Deep Details"
    case rainSummary = "Rain Summary"
    case windSummary = "Wind Summary"
    case radar = "Weather Radar"
    case uvIndex = "UV Index"
    case feelsLike = "Feels Like"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .hourlyForecast: return "chart.xyaxis.line"
        case .dailyForecast: return "calendar"
        case .deepDetails: return "speedometer"
        case .rainSummary: return "cloud.rain.fill"
        case .windSummary: return "wind"
        case .radar: return "tornado"
        case .uvIndex: return "sun.max.fill"
        case .feelsLike: return "thermometer.medium"
        }
    }
}



struct DashboardWidget: Codable, Identifiable, Equatable {
    let id: UUID
    let type: WidgetType
    var visibleMetrics: [WeatherMetric]? // Config for deepDetails
    
    static let defaultDashboard: [DashboardWidget] = [
        DashboardWidget(id: UUID(), type: .hourlyForecast),
        DashboardWidget(id: UUID(), type: .deepDetails, visibleMetrics: [.humidity, .feelsLike, .wind, .uvIndex, .rain, .visibility]),
        DashboardWidget(id: UUID(), type: .dailyForecast),
        DashboardWidget(id: UUID(), type: .radar)
    ]
}

enum WeatherSection: String, Codable, Identifiable, CaseIterable {
    static let sectionOrderChanged = Notification.Name("BreezySectionOrderChanged")

    case hourlyForecast
    case dailyForecast
    case metricsPills
    case sunMoon // Legacy for migration
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .hourlyForecast: return "24-Hour Forecast"
        case .dailyForecast: return "10-Day Forecast"
        case .metricsPills: return "Deep Details"
        case .sunMoon: return ""
        }
    }
    
    var icon: String {
        switch self {
        case .hourlyForecast: return "chart.xyaxis.line"
        case .dailyForecast: return "calendar"
        case .metricsPills: return "speedometer"
        case .sunMoon: return "sunset.fill"
        }
    }
    
    static var defaultOrder: [WeatherSection] {
        return [.hourlyForecast, .metricsPills, .dailyForecast]
    }
}

