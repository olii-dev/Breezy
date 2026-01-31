//
//  WatchWeatherViewModel.swift
//  BreezyWatch Watch App
//
//  View model for Watch app
//

import Foundation
import SwiftUI

class WatchWeatherViewModel: ObservableObject {
    @Published var weather: WatchWeatherData?
    @Published var isLoading = false
    
    @Published var themeMode: String = "Weather" // Raw string for now to match logic
    @Published var connectedMapStyle: String = "Standard"
    @Published var useMinimalistIcons: Bool = true
    @Published var connectedMapStyle: String = "Standard"
    @Published var useMinimalistIcons: Bool = true
    @Published var presetTheme: String = "Cotton Candy"
    @Published var typography: String = "System"
    
    @Published var activeThemeColors: (top: String, bottom: String, text: String)?
    
    // Add other necessary properties as they are added to the context
    
    init() {
        // Initialize Cloud Storage (starts observing)
        _ = WatchCloudStorage.shared
        
        // Load persisted theme colors (Local or Cloud)
        updateThemeFromStorage()
        
        // Observe Cloud Changes
        // DISABLED per user request for "No Sync Strategy"
        // NotificationCenter.default.addObserver(
        //     self,
        //     selector: #selector(handleCloudUpdate),
        //     name: .watchCloudDataReconciled,
        //     object: nil
        // )
        
        WatchSessionManager.shared.viewModel = self
        WatchSessionManager.shared.startSession()
        
        loadLayout()
        
        Task {
            await loadWeather()
        }
    }
    
    @objc private func handleCloudUpdate() {
        print("⌚️ WATCH: Handling Cloud Update")
        DispatchQueue.main.async {
            self.updateThemeFromStorage()
        }
    }
    
    private func updateThemeFromStorage() {
        if let top = WatchCloudStorage.shared.string(forKey: "Breezy.theme.top"),
           let bottom = WatchCloudStorage.shared.string(forKey: "Breezy.theme.bottom"),
           let text = WatchCloudStorage.shared.string(forKey: "Breezy.theme.text") {
            self.activeThemeColors = (top, bottom, text)
        }
        
        // Also sync Icons from Cloud
        // Check if key exists by comparing against defaults or expected logic
        // Bool defaults to false if missing, so we need to be careful. 
        // Logic on phone is: default true.
        // We can inspect UserDefaults directly or wrap in WatchCloudStorage.
        // Let's rely on WatchCloudStorage.bool which falls back to CloudStore.bool.
        // CloudStore.bool returns false if key missing.
        // But the key "Breezy.useMinimalistIcons" is set on Phone.
        
        // Better: Check standard user defaults first (populated by CloudStorage notification)
        if let minimalist = UserDefaults.standard.object(forKey: "Breezy.useMinimalistIcons") as? Bool {
            self.useMinimalistIcons = minimalist
        } else {
            // Fallback to checking cloud store directly just in case (e.g. initial launch)
            // But NSUbiquitousKeyValueStore doesn't have a "contains" method, only Object(forKey).
            // Let's try to fetch it.
            // Actually, we can just rely on the existing logic in WatchCloudStorage which copies to UserDefaults.
            // If it's not in UserDefaults, check Cloud manually?
            // Let's just trust that if it's in Cloud, it will be in UserDefaults by the time this runs (after notification).
            // Logic:
        }
        
        // Let's be robust:
        let cloudStore = NSUbiquitousKeyValueStore.default
        if let val = cloudStore.object(forKey: "Breezy.useMinimalistIcons") as? Bool {
             self.useMinimalistIcons = val
             UserDefaults.standard.set(val, forKey: "Breezy.useMinimalistIcons")
        }
    }
    
    func updateFromContext(_ context: [String: Any]) {
        if let mapStyle = context["Breezy.mapStyle"] as? String {
            self.connectedMapStyle = mapStyle
            UserDefaults.standard.set(mapStyle, forKey: "Breezy.mapStyle")
        }
        if let minimalist = context["useMinimalistIcons"] as? Bool {
            self.useMinimalistIcons = minimalist
            UserDefaults.standard.set(minimalist, forKey: "Breezy.useMinimalistIcons")
        }
        if let type = context["typography"] as? String {
            self.typography = type
            UserDefaults.standard.set(type, forKey: "Breezy.typography")
        }
        
        // Trigger UI refresh
        objectWillChange.send()
    }
    
    func loadWeather() async {
        await MainActor.run {
            isLoading = true
        }
        
        // Load from shared App Group
        guard let defaults = UserDefaults(suiteName: "group.com.breezy.weather"),
              let data = defaults.data(forKey: "BreezyWidgetData") else {
            await MainActor.run {
                isLoading = false
            }
            return
        }
        
        let decoder = JSONDecoder()
        if let widgetData = try? decoder.decode(WidgetWeatherData.self, from: data) {
            // Convert WidgetWeatherData to WatchWeatherData
            await MainActor.run {
                self.weather = WatchWeatherData(
                    city: widgetData.city,
                    temperature: widgetData.temperature,
                    condition: widgetData.condition,
                    emoji: widgetData.emoji,
                    highTemp: widgetData.highTemp,
                    lowTemp: widgetData.lowTemp,
                    hourlyForecast: widgetData.hourlyForecast.map { hour in
                        WatchHourlyForecast(
                            time: hour.time,
                            temperature: hour.temperature,
                            emoji: hour.emoji,
                            condition: hour.condition ?? ""
                        )
                    },
                    uvIndex: widgetData.uvIndex,
                    pressure: widgetData.pressure,
                    windSpeed: widgetData.windSpeed,
                    rainChance: widgetData.rainChance,
                    feelsLike: nil, // WidgetData might mock this or we derive it? WidgetData has no feelsLike field in definition above? Wait, let's check WidgetData definition.
                    sunset: nil
                )
                isLoading = false
            }
        } else {
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    // MARK: - Layout Customization
    
    @Published var layoutSections: [WatchLayoutSection] = [] {
        didSet {
            // Persist order
            if let data = try? JSONEncoder().encode(layoutSections) {
                UserDefaults(suiteName: "group.com.breezy.weather")?.set(data, forKey: "WatchLayoutSections")
            }
        }
    }
    
    func loadLayout() {
        if let data = UserDefaults(suiteName: "group.com.breezy.weather")?.data(forKey: "WatchLayoutSections"),
           let sections = try? JSONDecoder().decode([WatchLayoutSection].self, from: data) {
            self.layoutSections = sections
        } else {
            // Default Layout
            self.layoutSections = [.overview, .hourly, .radar, .daily]
        }
    }
    
    func resetLayout() {
        self.layoutSections = [.overview, .hourly, .radar, .daily]
    }
}

enum WatchLayoutSection: String, Codable, Identifiable, CaseIterable {
    case overview = "Current Conditions"
    case hourly = "Hourly Forecast"
    case daily = "7-Day Forecast"
    case radar = "Precipitation Map"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .overview: return "thermometer.medium"
        case .hourly: return "clock"
        case .daily: return "calendar"
        case .radar: return "map"
        }
    }
}

// MARK: - Watch Data Models

struct WatchWeatherData {
    let city: String
    let temperature: String
    let condition: String
    let emoji: String
    let highTemp: String?
    let lowTemp: String?
    let hourlyForecast: [WatchHourlyForecast]
    
    // Extended Metrics
    var uvIndex: Int?
    var pressure: String?
    var windSpeed: String?
    var rainChance: String?
    var humidity: String?
    var visibility: String?
    var dewPoint: String?
    var cloudCover: String?
    var feelsLike: String?
    var sunset: String?
}

struct WatchHourlyForecast: Identifiable {
    let id = UUID()
    let time: String
    let temperature: String
    let emoji: String
    let condition: String
}

// MARK: - Widget Data Model (shared with iOS app)

struct WidgetWeatherData: Codable {
    let city: String
    let temperature: String
    let condition: String
    let emoji: String
    let highTemp: String?
    let lowTemp: String?
    let hourlyForecast: [WidgetHourlyForecast]
    let timestamp: Date
    let useMinimalistIcons: Bool?
    let uvIndex: Int?
    let pressure: String?
    let windSpeed: String?
    let rainChance: String?
    
    struct WidgetHourlyForecast: Codable {
        let time: String
        let temperature: String
        let emoji: String
        let condition: String?
    }
}
