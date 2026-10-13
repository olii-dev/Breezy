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
    case airQuality = "Air Quality"

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
        case .airQuality: return "aqi.medium"
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
        case .airQuality: return "🌫"
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
    case openMeteo
    case cache
}

enum WatchSelectedWeatherSource: String, Codable, CaseIterable, Identifiable {
    case weatherKit = "weatherkit"
    case openMeteo = "open-meteo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weatherKit:
            return "WeatherKit"
        case .openMeteo:
            return "Open-Meteo"
        }
    }

    var historicalStartDate: Date {
        switch self {
        case .weatherKit:
            return Calendar.current.date(from: DateComponents(year: 2021, month: 8, day: 1)) ?? .distantPast
        case .openMeteo:
            return Calendar.current.date(from: DateComponents(year: 1940, month: 1, day: 1)) ?? .distantPast
        }
    }

    var historicalAvailabilityDescription: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return "Data available from \(formatter.string(from: historicalStartDate))"
    }
}

struct WatchWeatherMetadata: Codable {
    let source: WatchWeatherDataSource
    let fetchedAt: Date
    var isStale: Bool
    let latitude: Double?
    let longitude: Double?
}

/// 15-minute precipitation step — feeds the rain countdown banner.
struct WatchMinuteForecast: Codable, Equatable, Identifiable {
    var id: Date { date }
    let date: Date
    /// mm/h equivalent for the 15-min step.
    let intensityMillimetersPerHour: Double
    let isPrecipitating: Bool
}

enum WatchMoonPhaseHelper {
    /// Open-Meteo's moon_phase fraction (0 = new, 0.5 = full) bucketed to a name.
    static func name(forFraction fraction: Double) -> String {
        switch fraction {
        case ..<0.0625, 0.9375...: return "New Moon"
        case ..<0.1875: return "Waxing Crescent"
        case ..<0.3125: return "First Quarter"
        case ..<0.4375: return "Waxing Gibbous"
        case ..<0.5625: return "Full Moon"
        case ..<0.6875: return "Waning Gibbous"
        case ..<0.8125: return "Last Quarter"
        default: return "Waning Crescent"
        }
    }
}

enum WatchAQIHelper {
    /// US EPA category for a US AQI index value.
    static func category(forUSIndex index: Int) -> String {
        switch index {
        case ...50: return "Good"
        case ...100: return "Moderate"
        case ...150: return "Unhealthy for Sensitive Groups"
        case ...200: return "Unhealthy"
        case ...300: return "Very Unhealthy"
        default: return "Hazardous"
        }
    }

    /// Green → yellow → orange → red → purple → maroon by US EPA bands.
    static func colorHex(forUSIndex index: Int) -> String {
        switch index {
        case ...50: return "4CD964"
        case ...100: return "F5D94B"
        case ...150: return "FF9F45"
        case ...200: return "F05B5B"
        case ...300: return "A070D6"
        default: return "8C3A3A"
        }
    }
}

struct WatchWeatherData: Codable {
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
    var metadata: WatchWeatherMetadata
    /// Sun events as instants — complications use them for day-progress arcs
    /// and Smart Stack relevance around sunrise/sunset.
    var sunriseDate: Date? = nil
    var sunsetDate: Date? = nil
    /// Next ~hour of 15-minute precipitation steps, when the source serves them.
    var minuteForecast: [WatchMinuteForecast]? = nil
    /// US EPA AQI scale, when available.
    var aqi: Int? = nil
    var aqiCategory: String? = nil
}

struct WatchHourlyForecast: Identifiable, Codable {
    var id: Date { date }

    let date: Date
    let time: String
    let temperature: String
    let emoji: String
    let iconName: String
    let condition: String
    /// e.g. "45%" — nil when the source didn't provide one.
    var precipitationChance: String? = nil
    /// Per-hour values so complication timeline entries stay accurate for
    /// hours between refreshes.
    var uvValue: Int? = nil
    var windSpeedText: String? = nil
    var humidityPercent: Int? = nil
}

struct WatchDailyForecast: Identifiable, Codable {
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
    /// VoiceOver: "Monday, high 24, low 14, rain 30%" — the low temp lives in
    /// bar geometry visually, so it must be spoken explicitly.
    var a11yDescription: String {
        var text = "\(dayName), high \(highTemp), low \(lowTemp)"
        if precipitationChance != "0%" {
            text += ", rain \(precipitationChance)"
        }
        return text
    }

    /// Moon phase for the evening of this day.
    var moonPhaseName: String? = nil
    /// 0…1 illuminated fraction.
    var moonIllumination: Double? = nil
    var moonrise: Date? = nil
    var moonset: Date? = nil
}

struct WatchHistoricalDay {
    let date: Date
    let condition: String
    let emoji: String
    let iconName: String
    let highTemp: String
    let lowTemp: String
    let precipChance: String?
    let maxWind: String?
    let hourlyTemps: [WatchTempPoint]
}

struct WatchTempPoint: Identifiable {
    let id = UUID()
    let index: Int
    let temp: Double
}

// MARK: - Radar Types

enum WatchRadarLayer: String, CaseIterable, Identifiable, Codable {
    case precipitation = "precipitation_new"
    case wind = "wind_new"
    case clouds = "clouds_new"
    case temperature = "temp_new"
    case pressure = "pressure_new"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .precipitation: return "Precipitation"
        case .wind: return "Wind"
        case .clouds: return "Clouds"
        case .temperature: return "Temperature"
        case .pressure: return "Pressure"
        }
    }

    var iconName: String {
        switch self {
        case .precipitation: return "cloud.rain.fill"
        case .wind: return "wind"
        case .clouds: return "cloud.fill"
        case .temperature: return "thermometer.medium"
        case .pressure: return "gauge.medium"
        }
    }

    var emoji: String {
        switch self {
        case .precipitation: return "🌧"
        case .wind: return "💨"
        case .clouds: return "☁️"
        case .temperature: return "🌡"
        case .pressure: return "⏲"
        }
    }

    var supportsRainViewer: Bool { self == .precipitation }

    func legendGradient(for source: WatchRadarPrecipitationSource) -> [(value: Double, hexColor: String, label: String)] {
        switch self {
        case .precipitation:
            if source == .rainViewer {
                return [
                    (0, "#00000000", "Light"),
                    (20, "#6CCB5F", ""),
                    (40, "#F3D250", ""),
                    (60, "#F58B2A", ""),
                    (80, "#E34A4A", ""),
                    (100, "#B7349B", "Heavy")
                ]
            } else {
                return [
                    (0, "#00000000", "0"),
                    (0.1, "#C89696", "0.1"),
                    (0.5, "#7878BE", "0.5"),
                    (1, "#6E6ECD", "1"),
                    (10, "#5050E1", "10"),
                    (50, "#1414FF", "50+ mm/h")
                ]
            }
        case .wind:
            return [
                (0, "#00000000", "0"),
                (5, "#94B6D6", "5"),
                (10, "#308DC4", "10"),
                (20, "#2F67B3", "20"),
                (40, "#1953A2", "40+ m/s")
            ]
        case .clouds:
            return [
                (0, "#00000000", "0%"),
                (25, "#BCC7CC", "25%"),
                (50, "#8E9CA3", "50%"),
                (75, "#5E6B72", "75%"),
                (100, "#2F393D", "100%")
            ]
        case .temperature:
            return [
                (-40, "#8C39DE", "-40"),
                (-20, "#3B6FCE", "-20"),
                (0, "#4FAFF1", "0"),
                (15, "#2EBC4D", "15"),
                (30, "#E8B929", "30"),
                (40, "#E04A1D", "40+ °C")
            ]
        case .pressure:
            return [
                (960, "#710D0D", "960"),
                (990, "#D64545", "990"),
                (1013, "#2BAE66", "1013"),
                (1030, "#3D7CD6", "1030"),
                (1060, "#0D1F71", "1060 hPa")
            ]
        }
    }
}

enum WatchRadarPrecipitationSource: String, CaseIterable, Identifiable, Codable {
    case rainViewer = "RainViewer"
    case openWeather = "OpenWeather"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var subtitle: String {
        switch self {
        case .rainViewer:
            return "Global radar mosaic."
        case .openWeather:
            return "Matches other Breezy layers."
        }
    }
}

enum WatchAppStorageKey {
    static let appGroup = "group.com.breezy.weather"
    static let weatherSource = "WatchWeatherSource"
    static let phoneWeatherSource = "Breezy.weatherSource"
    static let temperatureUnit = "Breezy.temperatureUnit"
    static let selectedLocationID = "WatchSelectedLocationID"
    static let savedLocations = "WatchSavedLocations"
    static let lastForecast = "WatchLastForecast"
    static let lastLatitude = "WatchLastLatitude"
    static let lastLongitude = "WatchLastLongitude"
    static let lastCity = "WatchLastCity"
    static let lastTemperature = "WatchLastTemperature"
    static let lastCondition = "WatchLastCondition"
    static let lastEmoji = "WatchLastEmoji"
    static let lastHighTemp = "WatchLastHighTemp"
    static let lastLowTemp = "WatchLastLowTemp"
    static let lastCacheTimestamp = "WatchLastCacheTimestamp"
    static let lastWeatherSource = "WatchLastWeatherSource"
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
    static let radarLayer = "Breezy.watch.radarLayer"
    static let radarPrecipitationSource = "Breezy.radarPrecipitationSource"
    static let radarShowLegend = "Breezy.watch.radarShowLegend"
    static let radarShowBaseMap = "Breezy.watch.radarShowBaseMap"
    static let radarAnimationEnabled = "Breezy.watch.radarAnimationEnabled"
}
