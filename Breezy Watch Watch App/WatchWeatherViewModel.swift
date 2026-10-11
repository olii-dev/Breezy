//
//  WatchWeatherViewModel.swift
//  Breezy Watch Watch App
//
//  View model for Watch app.
//

import Foundation
import SwiftUI
import Combine
import CoreLocation
import WeatherKit
import WidgetKit
#if os(watchOS)
import WatchKit
#endif


@MainActor
class WatchWeatherViewModel: ObservableObject {
    enum ThemeMode: String {
        case auto = "Auto"
        case preset = "Preset"
    }

    enum AppearanceMode: String, CaseIterable, Identifiable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"
        
        var id: String { rawValue }
    }
    @Published var weather: WatchWeatherData?
    @Published var isLoading = false
    @Published var error: String?
    @Published var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var useMinimalistIcons: Bool = true
    @Published var typography: WeatherFont = .system
    @Published var visibleMetrics: Set<WeatherMetric> = [.humidity, .pressure, .visibility, .dewPoint, .wind, .rain, .uvIndex]
    @Published var themeMode: ThemeMode = .auto
    @Published var appearanceMode: AppearanceMode = .system
    @Published var selectedPresetThemeName: String = "Ocean"
    @Published var savedLocations: [WatchSavedLocation] = []
    @Published var selectedLocationID: UUID? = nil // nil means "Current Location" (GPS)
    @Published var recentSearches: [WatchSavedLocation] = []


    
    private let weatherDataService = WatchWeatherDataService.shared
    private var temperatureUnit: WatchTemperatureUnit = .celsius
    private var windSpeedUnit: WindSpeedUnit = .metersPerSecond
    private var pressureUnit: PressureUnit = .hectopascals
    private var visibilityUnit: VisibilityUnit = .kilometers
    
    init() {
        temperatureUnit = WatchTemperatureUnit.fromUserDefaults()
        useMinimalistIcons = UserDefaults.standard.bool(forKey: "Breezy.useMinimalistIcons")
        
        loadLocations()
        
        checkLocationAuthorization()
        
        loadLayout()
        
        // Listen for temperature unit changes
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("WatchTemperatureUnitChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.temperatureUnit = WatchTemperatureUnit.fromUserDefaults()
                self?.loadUnitsFromUserDefaults()
                await self?.loadWeather()
            }
        }
        
        // Listen for icon preference changes
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("WatchIconPreferenceChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.useMinimalistIcons = UserDefaults.standard.bool(forKey: "Breezy.useMinimalistIcons")
                await self?.loadWeather()
            }
        }
        

        // Listen for context updates from iOS
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("WatchContextUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.loadContext()
            }
        }
        
        loadContext()
    }
    
    private func loadContext() {
        if let defaults = UserDefaults(suiteName: "group.com.breezy.weather") {
            // Typography
            if let typeRaw = defaults.string(forKey: "Breezy.typography"),
               let type = WeatherFont(rawValue: typeRaw) {
                self.typography = type
            }
            
            // Metrics
            if let data = defaults.data(forKey: "Breezy.visibleMetrics"),
               let decoded = try? JSONDecoder().decode(Set<WeatherMetric>.self, from: data) {
                self.visibleMetrics = decoded
            }
            
            // Theme
            if let modeRaw = defaults.string(forKey: "Breezy.themeMode"),
               let mode = ThemeMode(rawValue: modeRaw) {
                self.themeMode = mode
            }
            
            if let appearanceRaw = defaults.string(forKey: "Breezy.appearanceMode"),
               let appearance = AppearanceMode(rawValue: appearanceRaw) {
                self.appearanceMode = appearance
            }
            
            if let presetName = defaults.string(forKey: "Breezy.selectedPresetThemeName") {
                self.selectedPresetThemeName = presetName
            }
        }
        loadUnitsFromUserDefaults()
    }
    
    // MARK: - Location Management
    
    func addLocation(name: String, latitude: Double, longitude: Double) {
        let newLocation = WatchSavedLocation(name: name, latitude: latitude, longitude: longitude)
        savedLocations.append(newLocation)
        saveLocations()
        addToRecents(name: name, latitude: latitude, longitude: longitude)
        playHaptic(.success)
        selectLocation(newLocation.id) // Switch to it immediately
    }
    
    func removeLocation(at offsets: IndexSet) {
        let locationsToDelete = offsets.map { savedLocations[$0] }
        if let selected = selectedLocationID, locationsToDelete.contains(where: { $0.id == selected }) {
            selectedLocationID = nil // Fallback to GPS
        }
        
        savedLocations.remove(atOffsets: offsets)
        saveLocations()
        playHaptic(.click)
        
        Task {
             await loadWeather()
        }
    }
    
    func selectLocation(_ id: UUID?) {
        selectedLocationID = id
        playHaptic(.click)
        // Persist selection
        if let id = id {
            UserDefaults(suiteName: "group.com.breezy.weather")?.set(id.uuidString, forKey: "WatchSelectedLocationID")
        } else {
             UserDefaults(suiteName: "group.com.breezy.weather")?.removeObject(forKey: "WatchSelectedLocationID")
        }
        
        Task {
            await loadWeather()
        }
    }
    
    private func saveLocations() {
        if let data = try? JSONEncoder().encode(savedLocations) {
            UserDefaults(suiteName: "group.com.breezy.weather")?.set(data, forKey: "WatchSavedLocations")
        }
    }
    
    private func loadLocations() {
        let defaults = UserDefaults(suiteName: "group.com.breezy.weather")
        
        // Load Locations
        if let data = defaults?.data(forKey: "WatchSavedLocations"),
           let decoded = try? JSONDecoder().decode([WatchSavedLocation].self, from: data) {
            self.savedLocations = decoded
        }
        
        // Load Selection
        if let idStr = defaults?.string(forKey: "WatchSelectedLocationID"),
           let id = UUID(uuidString: idStr) {
            // Validate it exists
            if self.savedLocations.contains(where: { $0.id == id }) {
                self.selectedLocationID = id
            } else {
                self.selectedLocationID = nil
            }
        } else {
            self.selectedLocationID = nil
        }
        
        // Ensure "Current Location" is respected if selectedLocationID is nil
        // No action needed really, loadWeather handles nil
        
        loadRecentSearches()
    }
    
    private func loadRecentSearches() {
        if let data = UserDefaults(suiteName: "group.com.breezy.weather")?.data(forKey: "WatchRecentSearches"),
           let decoded = try? JSONDecoder().decode([WatchSavedLocation].self, from: data) {
            self.recentSearches = decoded
        }
    }
    
    func addToRecents(name: String, latitude: Double, longitude: Double) {
        let newRecent = WatchSavedLocation(name: name, latitude: latitude, longitude: longitude)
        // Remove existing if present (move to top)
        recentSearches.removeAll { $0.name == name }
        // Add to front
        recentSearches.insert(newRecent, at: 0)
        // Limit to 5
        if recentSearches.count > 5 {
            recentSearches = Array(recentSearches.prefix(5))
        }
        // Save
        if let data = try? JSONEncoder().encode(recentSearches) {
            UserDefaults(suiteName: "group.com.breezy.weather")?.set(data, forKey: "WatchRecentSearches")
        }
    }
    
    func deleteFromRecents(at offsets: IndexSet) {
        recentSearches.remove(atOffsets: offsets)
        if let data = try? JSONEncoder().encode(recentSearches) {
            UserDefaults(suiteName: "group.com.breezy.weather")?.set(data, forKey: "WatchRecentSearches")
        }
    }

    private func loadUnitsFromUserDefaults() {
        let defaults = UserDefaults.standard
        
        if let windRaw = defaults.string(forKey: "Breezy.windSpeedUnit"),
           let wind = WindSpeedUnit(rawValue: windRaw) {
            windSpeedUnit = wind
        }
        
        if let pressureRaw = defaults.string(forKey: "Breezy.pressureUnit"),
           let pressure = PressureUnit(rawValue: pressureRaw) {
            pressureUnit = pressure
        }
        
        if let visibilityRaw = defaults.string(forKey: "Breezy.visibilityUnit"),
           let visibility = VisibilityUnit(rawValue: visibilityRaw) {
            visibilityUnit = visibility
        }
    }
    
    func checkLocationAuthorization() {
        locationAuthorizationStatus = CLLocationManager().authorizationStatus
    }
    
    func loadWeather() async {
        await performWeatherLoad(playHaptics: false)
    }

    func refresh() async {
        await performWeatherLoad(playHaptics: true)
    }

    #if os(watchOS)
    func playHaptic(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }
    #endif

    func refreshStatusText(for weather: WatchWeatherData) -> String {
        let sourceLabel: String
        switch weather.metadata.source {
        case .phone:
            sourceLabel = "iPhone"
        case .weatherKit:
            sourceLabel = "WeatherKit"
        case .openMeteo:
            sourceLabel = "Open-Meteo"
        case .cache:
            sourceLabel = weather.metadata.isStale ? "Cached" : "Saved"
        }

        let timestamp = RelativeDateTimeFormatter().localizedString(for: weather.metadata.fetchedAt, relativeTo: Date())
        return "Updated \(timestamp) • \(sourceLabel)"
    }

    func toggleMetric(_ metric: WeatherMetric, isEnabled: Bool) {
        if isEnabled {
            visibleMetrics.insert(metric)
        } else {
            visibleMetrics.remove(metric)
        }

        if let defaults = UserDefaults(suiteName: WatchAppStorageKey.appGroup),
           let data = try? JSONEncoder().encode(visibleMetrics) {
            defaults.set(data, forKey: "Breezy.visibleMetrics")
        }

        playHaptic(.click)
    }

    func clearCachedWeather() {
        guard let defaults = UserDefaults(suiteName: WatchAppStorageKey.appGroup) else {
            return
        }

        let keysToRemove = [
            WatchAppStorageKey.lastLatitude,
            WatchAppStorageKey.lastLongitude,
            WatchAppStorageKey.lastCity,
            WatchAppStorageKey.lastTemperature,
            WatchAppStorageKey.lastCondition,
            WatchAppStorageKey.lastEmoji,
            WatchAppStorageKey.lastHighTemp,
            WatchAppStorageKey.lastLowTemp,
            WatchAppStorageKey.lastCacheTimestamp
        ]

        keysToRemove.forEach(defaults.removeObject(forKey:))
        weather = nil
        error = nil
    }

    private func performWeatherLoad(playHaptics: Bool) async {
        isLoading = true
        error = nil
        checkLocationAuthorization()
        
        do {
            let selectedLocation = selectedLocationID.flatMap { selectedID in
                savedLocations.first(where: { $0.id == selectedID })
            }

            self.weather = try await weatherDataService.fetchWeather(selectedLocation: selectedLocation)
            
            // Reload complications
            reloadComplications()
            
            isLoading = false
            if playHaptics {
                playHaptic(.success)
            }
            
        } catch {
            // Error Handling (Same as before)
            var errorMessage = error.localizedDescription
            if let nsError = error as NSError? {
                if nsError.domain.contains("WeatherDaemon") || nsError.domain.contains("WeatherKit") {
                    if nsError.code == 2 {
                        errorMessage = "WeatherKit authentication failed. Check the app ID setup."
                    } else {
                        errorMessage = "WeatherKit error: \(error.localizedDescription)"
                    }
                } else if nsError.domain.contains("WatchOpenMeteo") {
                    errorMessage = "Open-Meteo error: \(error.localizedDescription)"
                }
            }
            self.error = errorMessage
            isLoading = false
            checkLocationAuthorization()
            if playHaptics {
                playHaptic(.failure)
            }
        }
    }
    
    func requestLocationPermission() {
        Task {
            do {
                _ = try await WatchLocationHelper().requestLocationAndGetData()
                await loadWeather()
            } catch {
                // Error will be handled by loadWeather or shown in error state
            }
        }
    }
    
    // MARK: - Widget Reloading
    
    private func reloadComplications() {
        WidgetCenter.shared.reloadAllTimelines()
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
           var sections = try? JSONDecoder().decode([WatchLayoutSection].self, from: data) {
            // Migration: Remove .header if present (it's now pinned)
            sections.removeAll { $0 == .header }
            self.layoutSections = sections
        } else {
            // Default Layout (Header is pinned at top)
            self.layoutSections = [.metrics, .hourly]
        }
    }
    
    func resetLayout() {
        self.layoutSections = [.metrics, .hourly]
    }
}

// MARK: - Watch Weather Metrics

struct WatchWeatherMetrics {
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
}

enum WatchLayoutSection: String, Codable, Identifiable, CaseIterable {
    case header = "Overview"
    case hourly = "Hourly"
    case metrics = "Details"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .header: return "thermometer.medium"
        case .hourly: return "clock"
        case .metrics: return "list.bullet.rectangle.portrait"
        }
    }
}

extension WatchWeatherViewModel {
    
    var isDark: Bool {
        switch appearanceMode {
        case .light: return false
        case .dark: return true
        case .system: 
            // On Watch, system is almost always dark, but we can check if needed.
            // For now, let's assume default to dark for "System" on Watch unless we have systemEnvironment access,
            // but actually, we should respect the colorScheme environment value in the View.
            // However, VM doesn't have access to Environment.
            // So we'll use a heuristic or default to true (Dark) for Watch standard.
            // Or better: Current hour? No, that's Dynamic theme logic.
            // Let's standardly treat System as Dark on Watch for now, OR rely on a passed parameter.
            // Actually, best is to return true (Dark) as default for Watch.
            return true
        }
    }

    func currentTheme(isSystemDark: Bool = true) -> WatchWeatherTheme {
        let effectiveIsDark: Bool
        switch appearanceMode {
        case .light: effectiveIsDark = false
        case .dark: effectiveIsDark = true
        case .system: effectiveIsDark = isSystemDark
        }

        if themeMode == .auto {
            if let weather = weather {
                return WatchWeatherTheme.theme(for: weather.condition, isDark: effectiveIsDark)
            } else {
                // Default fallback
                return WatchWeatherTheme.theme(for: "clear", isDark: effectiveIsDark)
            }
        } else {
            // Find the selected preset
            if let preset = WatchWeatherTheme.presets.first(where: { $0.name == selectedPresetThemeName }) {
                return effectiveIsDark ? preset.dark : preset.light
            }
            // Fallback
            return (effectiveIsDark ? WatchWeatherTheme.presets.first?.dark : WatchWeatherTheme.presets.first?.light) ?? WatchWeatherTheme.theme(for: "clear", isDark: effectiveIsDark)
        }
    }
    
    func updateThemeMode(_ mode: ThemeMode) {
        themeMode = mode
        if let defaults = UserDefaults(suiteName: "group.com.breezy.weather") {
            defaults.set(mode.rawValue, forKey: "Breezy.themeMode")
        }
    }
    
    func updateAppearanceMode(_ mode: AppearanceMode) {
        appearanceMode = mode
        if let defaults = UserDefaults(suiteName: "group.com.breezy.weather") {
            defaults.set(mode.rawValue, forKey: "Breezy.appearanceMode")
        }
    }
    
    func updateSelectedPreset(_ name: String) {
        selectedPresetThemeName = name
        themeMode = .preset // Automatically switch to preset mode
        if let defaults = UserDefaults(suiteName: "group.com.breezy.weather") {
            defaults.set(name, forKey: "Breezy.selectedPresetThemeName")
            defaults.set(ThemeMode.preset.rawValue, forKey: "Breezy.themeMode")
        }
    }
    
    func theme(for condition: String, isSystemDark: Bool = true) -> WatchWeatherTheme {
        if themeMode == .auto {
            let effectiveIsDark: Bool
            switch appearanceMode {
            case .light: effectiveIsDark = false
            case .dark: effectiveIsDark = true
            case .system: effectiveIsDark = isSystemDark
            }
            return WatchWeatherTheme.theme(for: condition, isDark: effectiveIsDark)
        } else {
            return currentTheme(isSystemDark: isSystemDark)
        }
    }
}
