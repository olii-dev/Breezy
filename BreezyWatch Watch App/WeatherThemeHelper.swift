//
//  WeatherThemeHelper.swift
//  BreezyWatch Watch App
//
//  Weather theme helper matching iOS app
//

import SwiftUI

struct WeatherThemeHelper {
    static func gradientColors(for condition: String, themeMode: String = "Weather", presetName: String? = nil) -> [Color] {
        // If Custom or Preset, return fixed colors (Simplified for Watch)
        if themeMode == "Pro Theme" || themeMode == "Custom" {
            // Check for matching preset
            if let presetName = presetName,
               let match = WatchTheme.presets.first(where: { $0.name == presetName }) {
                // Always use dark variant for Watch
                return [match.dark.topColor, match.dark.bottomColor]
            }
            
            // Fallback
            if themeMode == "Pro Theme" {
               // Fallback for custom or unknown presets
               return [Color.purple.opacity(0.5), Color.orange.opacity(0.4)]
            }
        }
        
        let cond = condition.lowercased()
        
        // Watch typically uses dark mode, but we'll match iOS app logic
        if cond.contains("night") || cond.contains("clear night") || cond.contains("clear") {
            return [Color.indigo.opacity(0.7), Color.black.opacity(0.8)]
        }
        if cond.contains("sun") || cond.contains("sunny") {
            return [Color.orange.opacity(0.4), Color.purple.opacity(0.6)]
        }
        if cond.contains("rain") || cond.contains("drizzle") {
            return [Color.blue.opacity(0.5), Color.gray.opacity(0.8)]
        }
        if cond.contains("cloud") || cond.contains("overcast") {
            return [Color.gray.opacity(0.6), Color.blue.opacity(0.7)]
        }
        if cond.contains("snow") || cond.contains("blizzard") {
            return [Color.blue.opacity(0.4), Color.cyan.opacity(0.5)]
        }
        if cond.contains("fog") || cond.contains("mist") {
            return [Color.gray.opacity(0.5), Color.black.opacity(0.7)]
        }
        if cond.contains("thunder") || cond.contains("storm") {
            return [Color.purple.opacity(0.6), Color.indigo.opacity(0.8)]
        }
        // Default
        return [Color.blue.opacity(0.5), Color.indigo.opacity(0.7)]
    }
}
