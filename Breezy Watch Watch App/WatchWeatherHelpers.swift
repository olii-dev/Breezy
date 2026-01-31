//
//  WatchWeatherHelpers.swift
//  Breezy Watch Watch App
//
//  Weather parsing helper functions for Watch app
//

import Foundation
import WeatherKit

struct WatchWeatherConditionConverter {
    static func description(from condition: WeatherCondition) -> String {
        switch condition {
        case .clear: return "Clear"
        case .cloudy: return "Cloudy"
        case .foggy: return "Foggy"
        case .haze: return "Haze"
        case .mostlyClear: return "Mostly Clear"
        case .mostlyCloudy: return "Mostly Cloudy"
        case .partlyCloudy: return "Partly Cloudy"
        case .smoky: return "Smoky"
        case .breezy: return "Breezy"
        case .windy: return "Windy"
        case .drizzle: return "Drizzle"
        case .heavyRain: return "Heavy Rain"
        case .rain: return "Rain"
        case .sunShowers:
            return "Sun Showers"
        case .blowingDust:
            return "Blowing Dust"
        case .freezingDrizzle: return "Freezing Drizzle"
        case .freezingRain: return "Freezing Rain"
        case .sleet: return "Sleet"
        case .snow: return "Snow"
        case .heavySnow: return "Heavy Snow"
        case .sunFlurries: return "Sun Flurries"
        case .flurries: return "Flurries"
        case .blowingSnow: return "Blowing Snow"
        case .blizzard: return "Blizzard"
        case .frigid: return "Frigid"
        case .hot: return "Hot"
        case .hail: return "Hail"
        case .scatteredThunderstorms: return "Scattered Thunderstorms"
        case .strongStorms: return "Strong Storms"
        case .thunderstorms: return "Thunderstorms"
        case .isolatedThunderstorms: return "Isolated Thunderstorms"
        case .tropicalStorm: return "Tropical Storm"
        case .hurricane: return "Hurricane"
        @unknown default: return "Unknown"
        }
    }
}

struct WatchWeatherIconHelper {
    static func emoji(for condition: String) -> String {
        let cond = condition.lowercased()
        
        if cond.contains("clear") {
            if isNightTime() {
                return "🌙"
            }
            return "☀️"
        }
        
        if cond.contains("sun") || cond.contains("sunny") { return "☀️" }
        if cond.contains("rain") || cond.contains("drizzle") { return "🌧️" }
        if cond.contains("cloud") || cond.contains("overcast") { return "⛅️" }
        if cond.contains("snow") || cond.contains("blizzard") { return "❄️" }
        if cond.contains("fog") || cond.contains("mist") { return "🌫️" }
        if cond.contains("thunder") { return "⛈️" }
        
        if isNightTime() {
            return "🌙"
        }
        
        return "🌡️"
    }
    
    static func minimalistIcon(for condition: String) -> String {
        let cond = condition.lowercased()
        
        if cond.contains("clear") && (cond.contains("night") || isNightTime()) {
            return "moon.stars"
        }
        
        if cond.contains("sun") || cond.contains("clear") || cond.contains("sunny") {
            return "sun.max"
        }
        if cond.contains("rain") || cond.contains("drizzle") { return "cloud.rain" }
        if cond.contains("cloud") || cond.contains("overcast") { return "cloud" }
        if cond.contains("snow") || cond.contains("blizzard") { return "snow" }
        if cond.contains("fog") || cond.contains("mist") { return "cloud.fog" }
        if cond.contains("thunder") { return "cloud.bolt" }
        if cond.contains("wind") || cond.contains("breeze") || cond.contains("gust") { return "wind" }

        return "thermometer.medium"
    }
    
    private static func isNightTime() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 20 || hour < 6
    }
}

struct WatchDateFormatterHelper {
    static func formatHour(_ hour: Int) -> String {
        hour == 0 ? "12AM" :
        hour < 12 ? "\(hour)AM" :
        hour == 12 ? "12PM" : "\(hour - 12)PM"
    }
    
    static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct WatchWindDirectionHelper {
    static func cardinalDirection(from degrees: Double) -> String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                         "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((degrees + 11.25) / 22.5) % 16
        return directions[index]
    }
}

enum WatchTemperatureUnit: String {
    case celsius = "celsius"
    case fahrenheit = "fahrenheit"
    
    var symbol: String {
        switch self {
        case .celsius: return "C"
        case .fahrenheit: return "F"
        }
    }
    
    static func fromUserDefaults() -> WatchTemperatureUnit {
        // Read from shared UserDefaults (same key as iOS app)
        if let defaults = UserDefaults(suiteName: "group.com.breezy.weather"),
           let unitString = defaults.string(forKey: "Breezy.temperatureUnit"),
           let unit = WatchTemperatureUnit(rawValue: unitString) {
            return unit
        }
        // Fallback to iOS app's UserDefaults
        if let unitString = UserDefaults.standard.string(forKey: "Breezy.temperatureUnit"),
           let unit = WatchTemperatureUnit(rawValue: unitString) {
            return unit
        }
        return .celsius
    }
}

