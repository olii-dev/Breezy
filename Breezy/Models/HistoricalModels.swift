//
//  HistoricalModels.swift
//  Breezy
//
//  Models for Time Machine Compare Mode and Historical Charts
//

import Foundation

// MARK: - Historical Data Point (for Charts)

struct HistoricalDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let temperature: Double  // in Celsius
    let high: Double?
    let low: Double?
    let condition: String?
}

// MARK: - Weather Comparison (for Compare Mode)

struct WeatherComparison {
    let current: WeatherInfo
    let past: WeatherInfo
    
    // Computed deltas
    var tempDelta: String {
        // Extract numeric values from temperature strings
        guard let currentTemp = extractTemp(from: current.temperature),
              let pastTemp = extractTemp(from: past.temperature) else {
            return "—"
        }
        
        let delta = currentTemp - pastTemp
        let sign = delta >= 0 ? "+" : ""
        return String(format: "%@%.0f°", sign, delta)
    }
    
    var isWarmer: Bool {
        guard let currentTemp = extractTemp(from: current.temperature),
              let pastTemp = extractTemp(from: past.temperature) else {
            return false
        }
        return currentTemp > pastTemp
    }
    
    var isCooler: Bool {
        guard let currentTemp = extractTemp(from: current.temperature),
              let pastTemp = extractTemp(from: past.temperature) else {
            return false
        }
        return currentTemp < pastTemp
    }
    
    var conditionChanged: Bool {
        return current.condition.lowercased() != past.condition.lowercased()
    }
    
    // Helper to extract numeric temperature from "72°F" or "72°C"
    private func extractTemp(from string: String) -> Double? {
        let cleaned = string.replacingOccurrences(of: "°F", with: "")
            .replacingOccurrences(of: "°C", with: "")
            .replacingOccurrences(of: "°", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }
}
