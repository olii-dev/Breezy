//
//  WeatherMetrics.swift
//  Breezy
//
//  Additional weather metrics model
//

import Foundation

struct WeatherMetrics: Codable, Equatable {
    let uvIndex: Int?
    let uvIndexCategory: String? // Low, Moderate, High, Very High, Extreme
    let airQuality: AirQuality?
    let marine: MarineConditions?
    let pressure: String? // in hPa or inHg
    let visibility: String? // in km or miles
    let dewPoint: String? // temperature
    let humidity: Int? // percentage
    let windDirection: Double? // degrees (0-360)
    let windDirectionCardinal: String? // N, NE, E, SE, S, SW, W, NW
    let windSpeed: String? // wind speed in mph or km/h
    let windGust: String? // wind gust speed in mph or km/h
    let rainChance: String? // percentage
    let todayRainfall: String? // total rainfall today (e.g., "2.4 mm")
    let todayMaxRainIntensity: String? // max intensity today (e.g., "4 mm/h")
    let cloudCover: String? // percentage
    let sunrise: String? // time string
    let sunset: String? // time string
    let minuteForecast: [MinuteForecast]? // next 60 minutes of precipitation
}

struct AirQuality: Codable, Equatable {
    let aqi: Int? // Air Quality Index
    let category: String? // Good, Moderate, Unhealthy for Sensitive Groups, Unhealthy, Very Unhealthy, Hazardous
    let dominantPollutant: String?
}

struct MarineConditions: Codable, Equatable {
    let waveHeight: String?
    let waveDirection: String?
    let wavePeriod: String?
    let swellHeight: String?
    let seaSurfaceTemperature: String?
    let currentSpeed: String?
    let currentDirection: String?
}

struct MoonPhase: Codable, Equatable {
    let phase: String // New Moon, Waxing Crescent, First Quarter, Waxing Gibbous, Full Moon, Waning Gibbous, Last Quarter, Waning Crescent
    let illumination: Double // 0.0 to 1.0
    let icon: String
}
