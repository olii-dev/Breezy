//
//  WatchIconHelper.swift
//  BreezyWatch Watch App
//
//  Weather condition icon/emoji helpers
//

import Foundation

struct WatchIconHelper {
    static func emoji(for condition: String) -> String {
        let cond = condition.lowercased()
        
        if cond.contains("clear") {
            let hour = Calendar.current.component(.hour, from: Date())
            if hour >= 20 || hour < 6 {
                return "🌙"
            }
            return "☀️"
        }
        
        if cond.contains("sun") || cond.contains("sunny") {
            return "☀️"
        }
        if cond.contains("rain") || cond.contains("drizzle") { return "🌧️" }
        if cond.contains("cloud") || cond.contains("overcast") { return "⛅️" }
        if cond.contains("snow") || cond.contains("blizzard") { return "❄️" }
        if cond.contains("fog") || cond.contains("mist") { return "🌫️" }
        if cond.contains("thunder") { return "⛈️" }
        if cond.contains("wind") || cond.contains("breeze") || cond.contains("gust") { return "💨" }

        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 20 || hour < 6 {
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
