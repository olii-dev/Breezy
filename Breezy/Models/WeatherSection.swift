//
//  WeatherSection.swift
//  Breezy
//
//  Model for reorderable weather sections
//

import Foundation

enum WidgetType: String, Codable, CaseIterable, Identifiable {
    // Forecasts
    case hourlyForecast = "Hourly Forecast"
    case dailyForecast = "Daily Forecast"
    case forecastNarrative = "Forecast Narrative"
    case hourlyTemperatures = "Hourly Temperatures"
    
    // Details
    case deepDetails = "Deep Details"
    case rainSummary = "Rain Summary"
    case rainfallToday = "Rainfall Today"
    case minutePrecipitation = "Next 60 Minutes"
    case windSummary = "Wind Summary"
    case windGraph = "Wind Graph"
    case uvIndex = "UV Index"
    case feelsLike = "Feels Like"
    case uvIndexCurve = "UV Index Curve"
    case humidityStrip = "Humidity"
    case precipitationTimeline = "Precip Timeline"
    case visibilityCard = "Visibility"
    case cloudCoverCard = "Cloud Cover"
    case windHistory = "Wind History"
    
    // Astronomy
    case sunPath = "Sun Path"
    case moonPhase = "Moon Phase"
    
    // Maps
    case radar = "Weather Radar"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .hourlyForecast: return "chart.xyaxis.line"
        case .dailyForecast: return "calendar"
        case .forecastNarrative: return "text.justify.left"
        case .deepDetails: return "speedometer"
        case .rainSummary: return "cloud.rain.fill"
        case .rainfallToday: return "drop.fill"
        case .minutePrecipitation: return "chart.bar.fill"
        case .windSummary: return "wind"
        case .windGraph: return "chart.line.uptrend.xyaxis"
        case .radar: return "tornado"
        case .uvIndex: return "sun.max.fill"
        case .feelsLike: return "thermometer.medium"
        case .hourlyTemperatures: return "thermometer.sun.fill"
        case .humidityStrip: return "humidity.fill"
        case .precipitationTimeline: return "chart.bar.xaxis"
        case .visibilityCard: return "eye.fill"
        case .cloudCoverCard: return "cloud.fill"
        case .windHistory: return "lines.measurement.horizontal"
        case .sunPath: return "sun.and.horizon.fill"
        case .moonPhase: return "moon.stars.fill"
        case .uvIndexCurve: return "chart.xyaxis.line"
        }
    }
}



struct DashboardWidget: Codable, Identifiable, Equatable {
    let id: UUID
    let type: WidgetType
    var visibleMetrics: [WeatherMetric]? // Config for deepDetails
    var config: [String: String]? // Generic config (e.g. ["style": "rose"] for wind)
    
    static let defaultDashboard: [DashboardWidget] = [
        DashboardWidget(id: UUID(), type: .hourlyForecast),
        DashboardWidget(id: UUID(), type: .deepDetails, visibleMetrics: [.humidity, .feelsLike, .wind, .uvIndex, .rain, .visibility]),
        DashboardWidget(id: UUID(), type: .dailyForecast),
        DashboardWidget(id: UUID(), type: .forecastNarrative),
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



// MARK: - Widget Categories for Gallery Grouping

enum WidgetCategory: String, CaseIterable, Identifiable {
    case forecasts = "Forecasts"
    case details = "Details"
    case astronomy = "Astronomy"
    case maps = "Maps"
    
    var id: String { rawValue }
}

extension WidgetType {
    var category: WidgetCategory {
        switch self {
        case .hourlyForecast, .dailyForecast, .forecastNarrative, .hourlyTemperatures, .precipitationTimeline:
            return .forecasts
        case .deepDetails, .rainSummary, .rainfallToday, .minutePrecipitation, .windSummary, .windGraph, .uvIndex, .feelsLike, .uvIndexCurve, .humidityStrip, .visibilityCard, .cloudCoverCard, .windHistory:
            return .details
        case .sunPath, .moonPhase:
            return .astronomy
        case .radar:
            return .maps
        }
    }

    var supportsConfiguration: Bool {
        switch self {
        case .hourlyForecast, .deepDetails, .forecastNarrative, .minutePrecipitation, .windSummary, .windGraph, .uvIndex, .sunPath, .moonPhase, .humidityStrip, .windHistory:
            return true
        default:
            return false
        }
    }
}
