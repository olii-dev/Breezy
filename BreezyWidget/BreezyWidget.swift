//
//  BreezyWidget.swift
//  BreezyWidget
//
//  Weather widget for Breezy app
//  Supports Small, Medium, and Large widgets
//

import WidgetKit
import SwiftUI
import Foundation
import CoreLocation
import WeatherKit

// MARK: - Unit Enums (Duplicated for Widget Usage)

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

// MARK: - Helper for Forecast Items (Extension)


// MARK: - Shared Data Models

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
    let rainAmount: String?
    let latitude: Double?
    let longitude: Double?
    
    // New fields for accuracy
    let conditionCode: String?
    let isDaylight: Bool?
    let minTemp: String?

    let maxTemp: String?
    let humidity: String?
    let visibility: String?
    
    // Astronomy Data
    let sunrise: Date?
    let sunset: Date?
    let moonPhase: String? // e.g. "Waxing Crescent"
    let moonIllumination: Double? // 0.0 to 1.0
    let windDirectionDegrees: Double? // Added for gauge
    
    let dailyForecast: [WidgetDailyForecast]
    

    
    struct WidgetHourlyForecast: Codable {
        let time: String
        let temperature: String
        let emoji: String
        let condition: String
    }
    
    struct WidgetDailyForecast: Codable {
        let dayName: String
        let highTemp: String
        let lowTemp: String
        let condition: String
    }
}

// MARK: - Widget Location Manager
// MARK: - Widget Location Manager
class WidgetLocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = WidgetLocationManager()
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var locationTask: Task<CLLocation, Error>?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    
    func requestLocation() async throws -> CLLocation {
        // Cancel existing task if any
        locationTask?.cancel()
        
        // OPTIMIZATION: Check if we have a recent location cached by the system
        if let lastLocation = manager.location, 
           lastLocation.timestamp.timeIntervalSinceNow > -300 { // 5 mins
            print("Widget: Using recent system location (Age: \(Int(-lastLocation.timestamp.timeIntervalSinceNow))s)")
            return lastLocation
        }
        
        locationTask = Task {
            try await withCheckedThrowingContinuation { cont in
                // Ensure single resumption
                let state = ContinuationState(cont: cont)
                self.continuation = nil // Reset old one if any, though Task handles it
                
                // Set up local continuation handler
                self.continuationHandler = { result in
                    state.resume(with: result)
                }
                
                // Check auth
                let status = manager.authorizationStatus
                guard status == .authorizedWhenInUse || status == .authorizedAlways else {
                    self.continuationHandler?(.failure(NSError(domain: "WidgetLocation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not authorized"])))
                    return
                }
                
                manager.requestLocation()
                
                // Timeout
                DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
                    self.continuationHandler?(.failure(NSError(domain: "WidgetLocation", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timeout"])))
                }
            }
        }
        
        return try await locationTask!.value
    }
    
    // Internal handler to bridge delegate to continuation safely
    private var continuationHandler: ((Result<CLLocation, Error>) -> Void)?
    
    // Thread-safe wrapper class
    private class ContinuationState {
        var continuation: CheckedContinuation<CLLocation, Error>?
        var isResumed = false
        private let lock = NSLock()
        
        init(cont: CheckedContinuation<CLLocation, Error>) {
            self.continuation = cont
        }
        
        func resume(with result: Result<CLLocation, Error>) {
            lock.lock()
            defer { lock.unlock() }
            guard !isResumed else { return }
            isResumed = true
            
            switch result {
            case .success(let loc): continuation?.resume(returning: loc)
            case .failure(let err): continuation?.resume(throwing: err)
            }
            continuation = nil
        }
    }
    
    @objc func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.first {
            continuationHandler?(.success(location))
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuationHandler?(.failure(error))
    }
}

// MARK: - Weather Data Store

struct WeatherDataStore {
    private static let key = "BreezyWidgetData"
    private static let lastRefreshKey = "BreezyLastRefresh"
    
    static var isDataFresh: Bool {
        guard let defaults = UserDefaults(suiteName: "group.com.breezy.weather"),
              let lastRefresh = defaults.object(forKey: lastRefreshKey) as? Date else {
            return false
        }
        let freshnessInterval: TimeInterval = 30 * 60 // 30 minutes
        return Date().timeIntervalSince(lastRefresh) < freshnessInterval
    }
    
    static func load() -> WidgetWeatherData? {
        guard let defaults = UserDefaults(suiteName: "group.com.breezy.weather") else {
            return nil
        }
        
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode(WidgetWeatherData.self, from: data) {
            return decoded
        } else {
            return nil
        }
    }
}

// MARK: - Weather Theme Helper

struct WeatherThemeHelper {
    static let defaults = UserDefaults(suiteName: "group.com.breezy.weather")
    
    static func gradientColors(for condition: String, isDark: Bool, conditionCode: String? = nil, isDaylight: Bool? = nil) -> [Color] {
        // 1. Determine Effective Dark Mode
        let appearanceMode = defaults?.string(forKey: "Breezy.appearanceMode") ?? "System"
        var effectiveIsDark = isDark
        
        if appearanceMode == "Dark" {
            effectiveIsDark = true
        } else if appearanceMode == "Light" {
            effectiveIsDark = false
        }
        
        // 2. Check App Theme Preference
        let themeModeRaw = defaults?.string(forKey: "Breezy.themeMode") ?? "Weather"
        
        if themeModeRaw == "Pro Theme" {
            // Use Preset
            let presetName = defaults?.string(forKey: "Breezy.presetTheme") ?? "Cotton Candy"
            if let preset = presets.first(where: { $0.name == presetName }) {
                let theme = effectiveIsDark ? preset.dark : preset.light
                // Adapt to Watch/Widget theme structure (Top/Bottom)
                return [theme.topColor, theme.bottomColor]
            }
        }
        
        // 3. Fallback to Weather-based (Auto)
        
        // We prioritise the App/System appearance preference (effectiveIsDark)
        // over the raw "isDaylight" flag, to ensure the UI matches the requested mode.
        // (The app uses isDark to switch between Light/Dark palettes).
        
        let code = conditionCode ?? condition
        return getGradient(for: code, isNight: effectiveIsDark, fallbackCondition: condition)
    }
    
    // MARK: - Presets Definition (Mirrored from App)
    struct WidgetTheme {
        let topColor: Color
        let bottomColor: Color
    }
    
    struct NamedTheme {
        let name: String
        let light: WidgetTheme
        let dark: WidgetTheme
    }
    
    static let presets: [NamedTheme] = [
        NamedTheme(
            name: "Cotton Candy",
            light: WidgetTheme(topColor: Color(red: 1.0, green: 0.76, blue: 0.63), bottomColor: Color(red: 1.0, green: 0.69, blue: 0.74)),
            dark: WidgetTheme(topColor: Color(red: 0.67, green: 0.39, blue: 0.45), bottomColor: Color(red: 0.55, green: 0.31, blue: 0.38))
        ),
        NamedTheme(
            name: "Ocean",
            light: WidgetTheme(topColor: Color(red: 0.13, green: 0.58, blue: 0.69), bottomColor: Color(red: 0.43, green: 0.84, blue: 0.93)),
            dark: WidgetTheme(topColor: Color(red: 0.06, green: 0.25, blue: 0.36), bottomColor: Color(red: 0.16, green: 0.32, blue: 0.60))
        ),
        NamedTheme(
            name: "Forest",
            light: WidgetTheme(topColor: Color(red: 0.44, green: 0.70, blue: 0.50), bottomColor: Color(red: 0.07, green: 0.31, blue: 0.37)),
            dark: WidgetTheme(topColor: Color(red: 0.11, green: 0.31, blue: 0.16), bottomColor: Color(red: 0.04, green: 0.17, blue: 0.15))
        ),
        NamedTheme(
            name: "Sunset",
            light: WidgetTheme(topColor: Color(red: 1.0, green: 0.32, blue: 0.18), bottomColor: Color(red: 0.87, green: 0.14, blue: 0.46)),
            dark: WidgetTheme(topColor: Color(red: 0.56, green: 0.14, blue: 0.14), bottomColor: Color(red: 0.35, green: 0.11, blue: 0.24))
        ),
        NamedTheme(
            name: "Midnight",
            light: WidgetTheme(topColor: Color(red: 0.56, green: 0.62, blue: 0.67), bottomColor: Color(red: 0.93, green: 0.95, blue: 0.95)),
            dark: WidgetTheme(topColor: Color(red: 0.14, green: 0.15, blue: 0.15), bottomColor: Color(red: 0.25, green: 0.26, blue: 0.27))
        ),
        NamedTheme(
            name: "Lavender",
            light: WidgetTheme(topColor: Color(red: 0.88, green: 0.76, blue: 0.99), bottomColor: Color(red: 0.56, green: 0.77, blue: 0.99)),
            dark: WidgetTheme(topColor: Color(red: 0.34, green: 0.24, blue: 0.50), bottomColor: Color(red: 0.23, green: 0.25, blue: 0.44))
        ),
        NamedTheme(
            name: "Royal",
            light: WidgetTheme(topColor: Color(red: 0.33, green: 0.41, blue: 0.46), bottomColor: Color(red: 0.16, green: 0.18, blue: 0.29)),
            dark: WidgetTheme(topColor: Color(red: 0.08, green: 0.12, blue: 0.19), bottomColor: Color(red: 0.14, green: 0.23, blue: 0.33))
        ),
        NamedTheme(
            name: "Mango",
            light: WidgetTheme(topColor: Color(red: 1.0, green: 0.89, blue: 0.35), bottomColor: Color(red: 1.0, green: 0.65, blue: 0.32)),
            dark: WidgetTheme(topColor: Color(red: 0.70, green: 0.49, blue: 0.13), bottomColor: Color(red: 0.55, green: 0.31, blue: 0.09))
        )
    ]
    
    private static func getGradient(for code: String, isNight: Bool, fallbackCondition: String) -> [Color] {
        let c = code.lowercased()
        
        if isNight {
            // Dark mode - soft but with depth
            if c.contains("sun") || c.contains("clear") {
                return [
                    Color(red: 0.45, green: 0.38, blue: 0.58),  // Deep lavender
                    Color(red: 0.35, green: 0.25, blue: 0.45)   // Deep purple
                ]
            } else if c.contains("rain") {
                return [
                    Color(red: 0.30, green: 0.40, blue: 0.50),  // Steel blue
                    Color(red: 0.20, green: 0.25, blue: 0.35)
                ]
            } else if c.contains("cloud") || c.contains("partly") {
                return [
                    Color(red: 0.40, green: 0.40, blue: 0.50),
                    Color(red: 0.30, green: 0.35, blue: 0.45)
                ]
            } else if c.contains("snow") {
                return [
                    Color(red: 0.40, green: 0.50, blue: 0.60),
                    Color(red: 0.30, green: 0.40, blue: 0.50)
                ]
            } else if c.contains("fog") || c.contains("mist") || c.contains("haze") {
                return [
                    Color(red: 0.35, green: 0.35, blue: 0.40),
                    Color(red: 0.25, green: 0.25, blue: 0.30)
                ]
            }
            // Default Night
            return [
                Color(red: 0.45, green: 0.38, blue: 0.58),
                Color(red: 0.35, green: 0.25, blue: 0.45)
            ]
        } else {
            // Light mode - beautiful soft pastels
            if c.contains("sun") || c.contains("clear") {
                return [
                    Color(red: 0.72, green: 0.83, blue: 0.95),  // Soft blue
                    Color(red: 0.97, green: 0.77, blue: 0.85)   // Soft pink
                ]
            } else if c.contains("rain") {
                return [
                    Color(red: 0.65, green: 0.75, blue: 0.85),  // Steel blue
                    Color(red: 0.83, green: 0.77, blue: 0.98)   // Lavender
                ]
            } else if c.contains("cloud") || c.contains("partly") {
                return [
                    Color(red: 0.8, green: 0.85, blue: 0.9),    // Soft gray-blue
                    Color(red: 0.83, green: 0.77, blue: 0.98)   // Lavender
                ]
            } else if c.contains("snow") {
                return [
                    Color(red: 0.9, green: 0.95, blue: 1.0),    // Icy blue
                    Color(red: 0.72, green: 0.83, blue: 0.95)   // Soft blue
                ]
            } else if c.contains("fog") || c.contains("mist") || c.contains("haze") {
                return [
                    Color(red: 0.9, green: 0.9, blue: 0.92),    // Light gray
                    Color(red: 0.95, green: 0.95, blue: 0.97)   // White
                ]
            }
            // Default Day
            return [
                Color(red: 0.72, green: 0.83, blue: 0.95),  // Soft blue
                Color(red: 0.83, green: 0.77, blue: 0.98)   // Lavender
            ]
        }
    }
}

// MARK: - Widget Icon Helper

struct WidgetIconHelper {
    
    // Function to choose icon style based on user preference and condition
    static func getIcon(for condition: String?, isMinimalist: Bool?, conditionCode: String? = nil, isDaylight: Bool? = nil) -> String {
        // Use default logic if new fields missing (for backward compatibility)
        let useMinimalist = isMinimalist ?? true
        
        // If we have precise condition code, use it
        if let code = conditionCode, let day = isDaylight {
            if useMinimalist {
                return minimalistIcon(for: code, isDaylight: day)
            } else {
                return emoji(for: code, isDaylight: day)
            }
        }
        
        // Fallback to old logic
        guard let condition = condition else { return "thermometer.medium" }
        
        if useMinimalist {
            return minimalistIcon(for: condition)
        } else {
            return emoji(for: condition)
        }
    }
    
    private static func isNightTime() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 20 || hour < 6
    }
    
    // Logic for SF Symbols (Precise)
    private static func minimalistIcon(for code: String, isDaylight: Bool) -> String {
        let c = code.lowercased()
        if c.contains("clear") || c.contains("sunny") { return isDaylight ? "sun.max" : "moon.stars" }
        if c.contains("partly") || c.contains("cloud") { return isDaylight ? "cloud.sun" : "cloud.moon" }
        if c.contains("rain") { return "cloud.rain" }
        if c.contains("drizzle") { return "cloud.drizzle" }
        if c.contains("thunder") { return "cloud.bolt" }
        if c.contains("snow") { return "snow" }
        if c.contains("fog") || c.contains("haze") { return "cloud.fog" }
        if c.contains("wind") { return "wind" }
        return isDaylight ? "sun.max" : "moon.stars"
    }

    // Logic for Emojis (Precise)
    private static func emoji(for code: String, isDaylight: Bool) -> String {
        let c = code.lowercased()
        if c.contains("clear") || c.contains("sunny") { return isDaylight ? "☀️" : "🌙" }
        if c.contains("partly") || c.contains("cloud") { return isDaylight ? "⛅️" : "☁️" }
        if c.contains("rain") { return "🌧️" }
        if c.contains("drizzle") { return "🌦️" }
        if c.contains("thunder") { return "⛈️" }
        if c.contains("snow") { return "❄️" }
        if c.contains("fog") || c.contains("haze") { return "🌫️" }
        return isDaylight ? "☀️" : "🌙"
    }
    
    // Legacy Logic (Fallback)
    private static func minimalistIcon(for condition: String) -> String {
        let cond = condition.lowercased()
        if cond.contains("clear") && (cond.contains("night") || isNightTime()) { return "moon.stars" }
        if cond.contains("sun") || cond.contains("clear") || cond.contains("sunny") { return "sun.max" }
        if cond.contains("rain") || cond.contains("drizzle") { return "cloud.rain" }
        if cond.contains("cloud") || cond.contains("overcast") { return "cloud" }
        if cond.contains("snow") || cond.contains("blizzard") { return "snow" }
        if cond.contains("fog") || cond.contains("mist") { return "cloud.fog" }
        if cond.contains("thunder") { return "cloud.bolt" }
        if cond.contains("wind") || cond.contains("breeze") || cond.contains("gust") { return "wind" }
        return "thermometer.medium"
    }
    
    private static func emoji(for condition: String) -> String {
        let cond = condition.lowercased()
        if cond.contains("clear") { return isNightTime() ? "🌙" : "☀️" }
        if cond.contains("sun") || cond.contains("sunny") { return "☀️" }
        if cond.contains("rain") || cond.contains("drizzle") { return "🌧️" }
        if cond.contains("cloud") || cond.contains("overcast") { return "⛅️" }
        if cond.contains("snow") || cond.contains("blizzard") { return "❄️" }
        if cond.contains("fog") || cond.contains("mist") { return "🌫️" }
        if cond.contains("thunder") { return "⛈️" }
        if cond.contains("wind") || cond.contains("breeze") || cond.contains("gust") { return "💨" }
        return isNightTime() ? "🌙" : "🌡️"
    }
}


// MARK: - Timeline Provider

struct Provider: TimelineProvider {
    
    // Note: All sample/preview/placeholder data was intentionally removed to ensure only real weather is shown.
    // Note: Using mock data for placeholder/gallery to avoid blank widgets
    func placeholder(in context: Context) -> WeatherEntry {
        WeatherEntry.mock
    }
    
    func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> ()) {
        if context.isPreview {
            completion(WeatherEntry.mock)
            return
        }

        let entry: WeatherEntry
        if let weather = WeatherDataStore.load() {
            entry = WeatherEntry(date: Date(), weather: weather)
        } else {
            // Provide minimal placeholder entry with no sample data
            entry = placeholder(in: context)
        }
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherEntry>) -> ()) {
        let currentDate = Date()
        let calendar = Calendar.current
        
        // 1. Load cached data first to check for coordinates
        guard let cachedData = WeatherDataStore.load() else {
            // No data at all - return placeholder and retry soon
            let entries = [placeholder(in: context)]
            let timeline = Timeline(entries: entries, policy: .after(currentDate.addingTimeInterval(15 * 60)))
            completion(timeline)
            return
        }
        
        // 2. Helper to create entries from data
        func createTimeline(from data: WidgetWeatherData) {
            var entries: [WeatherEntry] = []
            let calendar = Calendar.current
            
            // Create "Now" entry
            entries.append(WeatherEntry(date: Date(), weather: data))
            
            // Create future entries (next 4 hours, hourly)
            // WeatherKit returns hourly forecast, so we can use that to support future timeline
            for i in 1...4 {
                if let entryDate = calendar.date(byAdding: .hour, value: i, to: currentDate) {
                    
                    // Find matching hourly forecast
                    let hourComponent = calendar.component(.hour, from: entryDate)
                    var futureWeather = data
                    
                    // Try to finding matching hourly data
                    // Note: This matches the "12PM", "1AM" format from our lightweight model
                    // ideally we'd use the raw date from WeatherKit if we had it, but string matching works for now
                    let expectedTimeStr: String
                    if hourComponent == 0 { expectedTimeStr = "12AM" }
                    else if hourComponent < 12 { expectedTimeStr = "\(hourComponent)AM" }
                    else if hourComponent == 12 { expectedTimeStr = "12PM" }
                    else { expectedTimeStr = "\(hourComponent - 12)PM" }
                    
                    if let matchingForecast = data.hourlyForecast.first(where: { $0.time == expectedTimeStr }) {
                         futureWeather = WidgetWeatherData(
                            city: data.city,
                            temperature: matchingForecast.temperature,
                            condition: matchingForecast.condition ?? data.condition,
                            emoji: matchingForecast.emoji,
                            highTemp: data.highTemp,
                            lowTemp: data.lowTemp,
                            hourlyForecast: data.hourlyForecast,
                            timestamp: entryDate,
                            useMinimalistIcons: data.useMinimalistIcons,
                            uvIndex: data.uvIndex,
                            pressure: data.pressure,
                            windSpeed: data.windSpeed,
                            rainChance: data.rainChance,
                            rainAmount: data.rainAmount,
                            latitude: data.latitude,
                            longitude: data.longitude,
                            conditionCode: data.conditionCode, // Use parent's condition code/daylight for now or map?
                            isDaylight: data.isDaylight,       // Best guess: same as parent unless we calculate sunrise/set for every hour
                            minTemp: data.minTemp,
                            maxTemp: data.maxTemp,
                            humidity: data.humidity,
                            visibility: data.visibility,
                            sunrise: data.sunrise,
                            sunset: data.sunset,
                            moonPhase: data.moonPhase,
                            moonIllumination: data.moonIllumination,
                            windDirectionDegrees: data.windDirectionDegrees,
                            dailyForecast: data.dailyForecast
                        )
                    }
                    
                    entries.append(WeatherEntry(date: entryDate, weather: futureWeather))
                }
            }
            
            // Refresh strategy: Active fetch every 30 minutes
            let timeline = Timeline(entries: entries, policy: .after(currentDate.addingTimeInterval(30 * 60)))
            completion(timeline)
        }
        
        // 3. Check for coordinates
        // Logic:
        // A. If "Follow GPS" is ON -> Try to get current location
        // B. If that fails OR if "Follow GPS" is OFF -> Use cached coordinates
        
        let defaults = UserDefaults(suiteName: "group.com.breezy.weather")
        let shouldFollowGPS = defaults?.bool(forKey: "Breezy.shouldFollowGPS") ?? false
        
        // We'll define a quick aligned struct for location
        struct Coord { let lat: Double; let lon: Double }
        
        // Define flow in a Task
        Task {
            var targetLocation: Coord? = nil
            
            // Try GPS if enabled
            if shouldFollowGPS {
                // We need a way to get location synchronously-ish or await it
                // Since CLLocationManager needs a delegate, we'll use a one-shot helper
                // Note: Widgets have limited time. We set a short timeout.
                do {
                    let loc = try await WidgetLocationManager.shared.requestLocation()
                    targetLocation = Coord(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
                    // Update cache for next time
                    defaults?.set(loc.coordinate.latitude, forKey: "LastLatitude")
                    defaults?.set(loc.coordinate.longitude, forKey: "LastLongitude")
                } catch {
                    print("Widget GPS failed: \(error). Falling back to cache.")
                }
            }
            
            // Fallback to cache if no target yet
            if targetLocation == nil {
                if let lat = cachedData.latitude, let lon = cachedData.longitude {
                    targetLocation = Coord(lat: lat, lon: lon)
                }
            }
            
            guard let coords = targetLocation else {
                 createTimeline(from: cachedData)
                 return 
            }
            
            // OPTIMIZATION: Check if data is already fresh (within 30 mins)
            // If app refreshed recently, skip API call and use cached data
            if WeatherDataStore.isDataFresh {
                print("📱 Widget: Data is fresh, using cache instead of fetching")
                createTimeline(from: cachedData)
                return
            }
            
                // 4. Fetch Fresh Data
             do {
                 let location = CLLocation(latitude: coords.lat, longitude: coords.lon)
                let weatherService = WeatherService.shared
                let weather = try await weatherService.weather(for: location)
                
                // Parse fresh data
                // Need to read user units prefs from App Group Defaults
                let defaults = UserDefaults(suiteName: "group.com.breezy.weather")
                
                // Units
                let tempUnitRaw = defaults?.string(forKey: "Breezy.temperatureUnit") ?? "Celsius"
                let windUnitRaw = defaults?.string(forKey: "Breezy.windSpeedUnit") ?? "m/s"
                let precipUnitRaw = defaults?.string(forKey: "Breezy.precipitationUnit") ?? "Millimeters"
                // let pressUnitRaw = defaults?.string(forKey: "Breezy.pressureUnit") ?? "hPa"
                // let visUnitRaw = defaults?.string(forKey: "Breezy.visibilityUnit") ?? "Kilometers"
                
                let isFahrenheit = tempUnitRaw == "Fahrenheit"
                let precipitationUnit = PrecipitationUnit(rawValue: precipUnitRaw) ?? .millimeters
                
                // Current Temp
                let currentTemp = weather.currentWeather.temperature
                let tempStr: String
                if isFahrenheit {
                    tempStr = String(format: "%.0f°", currentTemp.converted(to: .fahrenheit).value)
                } else {
                    tempStr = String(format: "%.0f°", currentTemp.converted(to: .celsius).value)
                }
                
                // High/Low
                let daily = weather.dailyForecast.first
                let highTemp = daily?.highTemperature
                let lowTemp = daily?.lowTemperature
                
                let highStr: String = (highTemp != nil) ? String(format: "%.0f°", isFahrenheit ? highTemp!.converted(to: .fahrenheit).value : highTemp!.converted(to: .celsius).value) : "--"
                let lowStr: String = (lowTemp != nil) ? String(format: "%.0f°", isFahrenheit ? lowTemp!.converted(to: .fahrenheit).value : lowTemp!.converted(to: .celsius).value) : "--"

                // Condition
                let condition = weather.currentWeather.condition.description
                let conditionCode = weather.currentWeather.condition.description 
                let isDaylight = weather.currentWeather.isDaylight
                let windDirectionDegrees = weather.currentWeather.wind.direction.converted(to: .degrees).value
                
                // Wind
                let windVal = weather.currentWeather.wind.speed
                let windStr: String
                if windUnitRaw == "km/h" {
                    windStr = String(format: "%.0f km/h", windVal.converted(to: .kilometersPerHour).value)
                } else if windUnitRaw == "mph" {
                    windStr = String(format: "%.0f mph", windVal.converted(to: .milesPerHour).value)
                } else if windUnitRaw == "Knots" {
                     windStr = String(format: "%.0f kn", windVal.converted(to: .knots).value)
                } else {
                    windStr = String(format: "%.0f m/s", windVal.converted(to: .metersPerSecond).value)
                }
                
                // Pressure (Simplifying to formatted string for now)
                let pressVal = weather.currentWeather.pressure
                let pressStr = String(format: "%.0f hPa", pressVal.converted(to: .hectopascals).value)
                
                // UV
                let uv = Int(weather.currentWeather.uvIndex.value)
                
                // Rain Chance
                let rainChanceVal = daily?.precipitationChance ?? 0.0
                let rainChanceStr = String(format: "%.0f%%", rainChanceVal * 100)
                let startOfToday = calendar.startOfDay(for: currentDate)
                let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? currentDate
                let todayHours = weather.hourlyForecast.filter { $0.date >= startOfToday && $0.date < endOfToday }
                let todayRainAmount = todayHours.reduce(0.0) { $0 + $1.precipitationAmount.value }
                let rainAmountStr = String(format: "%.1f %@", precipitationUnit.convert(todayRainAmount), precipitationUnit.symbol)
                
                // Humidity
                let humidityVal = weather.currentWeather.humidity
                let humidityStr = String(format: "%.0f%%", humidityVal * 100)
                
                // Visibility
                let visVal = weather.currentWeather.visibility
                let visStr = String(format: "%.1f km", visVal.converted(to: .kilometers).value)
                
                // Hourly (Next 12h)
                var hourlyForecasts: [WidgetWeatherData.WidgetHourlyForecast] = []
                let nextHours = weather.hourlyForecast.filter { $0.date >= currentDate }.prefix(12)
                
                for hour in nextHours {
                    let hDate = hour.date
                    let hComp = calendar.component(.hour, from: hDate)
                    
                    let timeStr: String
                    if hComp == 0 { timeStr = "12AM" }
                    else if hComp < 12 { timeStr = "\(hComp)AM" }
                    else if hComp == 12 { timeStr = "12PM" }
                    else { timeStr = "\(hComp - 12)PM" }
                    
                    let hTempStr: String
                    if isFahrenheit {
                        hTempStr = String(format: "%.0f°", hour.temperature.converted(to: .fahrenheit).value)
                    } else {
                        hTempStr = String(format: "%.0f°", hour.temperature.converted(to: .celsius).value)
                    }
                    
                    let hCond = hour.condition.description
                    let hEmoji: String = WidgetIconHelper.getIcon(for: hCond, isMinimalist: true) // Reuse helper if possible or map
                    
                    hourlyForecasts.append(WidgetWeatherData.WidgetHourlyForecast(
                        time: timeStr,
                        temperature: hTempStr,
                        emoji: hEmoji, // This might be SFSymbol string or Emoji. Let's assume helper returns SF Symbol name for now based on other code
                        condition: hCond
                    ))
                }
                
                // Parse Daily Forecast (Next 10 Days)
                var dailyForecasts: [WidgetWeatherData.WidgetDailyForecast] = []
                let dailyFormatter = DateFormatter()
                dailyFormatter.dateFormat = "EEEE" // Full Day Name (e.g., Monday)
                
                for day in weather.dailyForecast.prefix(10) {
                     let dayName: String
                     if calendar.isDateInToday(day.date) {
                         dayName = "Today"
                     } else {
                         dayName = dailyFormatter.string(from: day.date)
                     }
                     
                     let highStr_d: String
                     let lowStr_d: String
                     if isFahrenheit {
                         highStr_d = String(format: "%.0f°", day.highTemperature.converted(to: .fahrenheit).value)
                         lowStr_d = String(format: "%.0f°", day.lowTemperature.converted(to: .fahrenheit).value)
                     } else {
                         highStr_d = String(format: "%.0f°", day.highTemperature.converted(to: .celsius).value)
                         lowStr_d = String(format: "%.0f°", day.lowTemperature.converted(to: .celsius).value)
                     }
                     
                     dailyForecasts.append(WidgetWeatherData.WidgetDailyForecast(
                        dayName: dayName,
                        highTemp: highStr_d,
                        lowTemp: lowStr_d,
                        condition: day.condition.description
                     ))
                }
                
                // Create New Data Object
                
                // Fix: Reverse Geocode to get the correct city name for the new location
                // If we are following GPS and moved, we must update the city name.
                var finalCityName = cachedData.city
                if shouldFollowGPS {
                    // Start geocoding in parallel or just await it (fast enough usually)
                    let geocoder = CLGeocoder()
                    if let placemarks = try? await geocoder.reverseGeocodeLocation(location),
                       let place = placemarks.first {
                        finalCityName = place.locality ?? place.name ?? cachedData.city
                    }
                }
                
                let newData = WidgetWeatherData(
                    city: finalCityName, // Use the fresh city name
                    temperature: tempStr,
                    condition: condition,
                    emoji: "🌡️", // WidgetIconHelper handles emoji now based on condition
                    highTemp: highStr,
                    lowTemp: lowStr,
                    hourlyForecast: hourlyForecasts,
                    timestamp: currentDate,
                    useMinimalistIcons: cachedData.useMinimalistIcons,
                    uvIndex: uv,
                    pressure: pressStr,
                    windSpeed: windStr,
                    rainChance: rainChanceStr,
                    rainAmount: rainAmountStr,
                    latitude: coords.lat,
                    longitude: coords.lon,
                    conditionCode: conditionCode,
                    isDaylight: isDaylight,
                    minTemp: lowStr,
                    maxTemp: highStr,
                    humidity: humidityStr,
                    visibility: visStr,
                    sunrise: daily?.sun.sunrise,
                    sunset: daily?.sun.sunset,
                    moonPhase: daily?.moon.phase.description,
                    moonIllumination: getMoonIllumination(daily?.moon.phase),
                    windDirectionDegrees: windDirectionDegrees,
                    dailyForecast: dailyForecasts
                )
                
                print("✅ Widget: Fetched fresh data for \(cachedData.city)")
                createTimeline(from: newData)
                
            } catch {
                print("❌ Widget: Fetch failed: \(error.localizedDescription)")
                // Fallback to cached data if fetch fails
                createTimeline(from: cachedData)
            }
        }
        
        func getMoonIllumination(_ phase: MoonPhase?) -> Double {
            guard let phase = phase else { return 0.5 }
            switch phase {
            case .new: return 0.0
            case .waxingCrescent: return 0.25
            case .firstQuarter: return 0.5
            case .waxingGibbous: return 0.75
            case .full: return 1.0
            case .waningGibbous: return 0.75
            case .lastQuarter: return 0.5
            case .waningCrescent: return 0.25
            @unknown default: return 0.5
            }
        }
    }
    
}

struct WeatherEntry: TimelineEntry {
    let date: Date
    let weather: WidgetWeatherData
}

// MARK: - Helper Extension for Next Hours

extension WeatherEntry {
    /// Returns the next 3 hours from the current time
    /// The widget data should already be filtered to show "Now" + next 2 hours
    var nextThreeHours: [WidgetWeatherData.WidgetHourlyForecast] {
        // The hourly forecast is already filtered in saveWidgetData to show "Now" + next 2 hours
        return Array(weather.hourlyForecast.prefix(3))
    }
}

// MARK: - Widget Views

struct SmallWidgetView: View {
    let entry: WeatherEntry
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(entry.weather.city)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            
            Spacer()
            
            // Main weather display - centered
            VStack(spacing: 4) {
                let icon = WidgetIconHelper.getIcon(for: entry.weather.condition, isMinimalist: entry.weather.useMinimalistIcons)

                if entry.weather.useMinimalistIcons ?? true {
                    Image(systemName: icon)
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(.white)
                        .symbolRenderingMode(.hierarchical)
                } else {
                    Text(icon)
                        .font(.system(size: 40))
                }
                
                Text(entry.weather.temperature)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                
                Text(entry.weather.condition)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity)
            
            Spacer()
            
            // High/Low
            if let high = entry.weather.highTemp, let low = entry.weather.lowTemp {
                HStack(spacing: 4) {
                    Text("H:\(high)")
                        .font(.system(size: 10, weight: .medium))
                    Text("•")
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.5))
                    Text("L:\(low)")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .containerBackground(for: .widget) {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: gradientColors),
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 100, height: 100)
                    .blur(radius: 50)
                    .offset(x: -25, y: -15)
                
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 80, height: 80)
                    .blur(radius: 40)
                    .offset(x: 30, y: 25)
            }
        }
    }
    
    var gradientColors: [Color] {
        WeatherThemeHelper.gradientColors(for: entry.weather.condition, isDark: colorScheme == .dark)
    }
}

struct MediumWidgetView: View {
    let entry: WeatherEntry
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            // Left side - Current weather (centered vertically)
            VStack(spacing: 0) {
                Spacer()
                
                VStack(alignment: .center, spacing: 6) {
                    Text(entry.weather.city)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    
                    // Main icon
                    let icon = WidgetIconHelper.getIcon(for: entry.weather.condition, isMinimalist: entry.weather.useMinimalistIcons)
                    
                    if entry.weather.useMinimalistIcons ?? true {
                        Image(systemName: icon)
                            .font(.system(size: 44, weight: .light))
                            .foregroundColor(.white)
                            .symbolRenderingMode(.hierarchical)
                            .padding(.vertical, 4)
                    } else {
                        Text(icon)
                            .font(.system(size: 44))
                            .padding(.vertical, 4)
                    }
                    
                    Text(entry.weather.temperature)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    
                    Text(entry.weather.condition)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 4)
                    
                    if let high = entry.weather.highTemp, let low = entry.weather.lowTemp {
                        HStack(spacing: 4) {
                            Text("H:\(high)")
                                .font(.system(size: 11, weight: .medium))
                            Text("•")
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.5))
                            Text("L:\(low)")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity)
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
            
            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 1)
                .padding(.vertical, 16)
            
            // Right side - Hourly forecast
            VStack(spacing: 0) {
                Spacer()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.bottom, 2)
                    
                    ForEach(entry.nextThreeHours, id: \.time) { hour in
                        HStack(spacing: 8) {
                            Text(hour.time)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .frame(width: 36, alignment: .leading)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            
                            // Hourly Icon
                            let hourIcon = WidgetIconHelper.getIcon(for: hour.condition, isMinimalist: entry.weather.useMinimalistIcons)
                            
                            if entry.weather.useMinimalistIcons ?? true {
                                Image(systemName: hourIcon)
                                    .font(.system(size: 18, weight: .light))
                                    .foregroundColor(.white)
                                    .symbolRenderingMode(.hierarchical)
                            } else {
                                Text(hourIcon)
                                    .font(.system(size: 18))
                            }
                            
                            Spacer(minLength: 0)
                            
                            Text(hour.temperature)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 8)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(8)
                    }
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .containerBackground(for: .widget) {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: gradientColors),
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 120, height: 120)
                    .blur(radius: 50)
                    .offset(x: -40, y: -20)
                
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 100, height: 100)
                    .blur(radius: 45)
                    .offset(x: 50, y: 25)
            }
        }
        }
    }
    
    var gradientColors: [Color] {
        WeatherThemeHelper.gradientColors(for: entry.weather.condition, isDark: colorScheme == .dark)
    }
}

struct LargeWidgetView: View {
    let entry: WeatherEntry
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.weather.city)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    
                    Text("Updated \(timeAgo)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
            }
            .padding(.top, 16)
            .padding(.horizontal, 18)
            
            Spacer()
            
            // Current weather - centered (FIXED FONT SIZES)
            VStack(spacing: 8) {
                let icon = WidgetIconHelper.getIcon(for: entry.weather.condition, isMinimalist: entry.weather.useMinimalistIcons)

                if entry.weather.useMinimalistIcons ?? true {
                    Image(systemName: icon)
                        .font(.system(size: 50, weight: .light)) // Adjusted from 56
                        .foregroundColor(.white)
                        .symbolRenderingMode(.hierarchical)
                } else {
                    Text(icon)
                        .font(.system(size: 50)) // Adjusted from 56
                }
                
                Text(entry.weather.temperature)
                    .font(.system(size: 42, weight: .bold)) // Adjusted from 48
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                
                Text(entry.weather.condition)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                
                if let high = entry.weather.highTemp, let low = entry.weather.lowTemp {
                    HStack(spacing: 5) {
                        Text("H:\(high)")
                            .font(.system(size: 14, weight: .semibold))
                        Text("•")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                        Text("L:\(low)")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                }
            }
            .frame(maxWidth: .infinity)
            
            Spacer()
            
            // Hourly forecast
            VStack(alignment: .leading, spacing: 10) {
                Text("Today")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                
                VStack(spacing: 6) {
                    ForEach(entry.nextThreeHours, id: \.time) { hour in
                        HStack(spacing: 12) {
                            Text(hour.time)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .frame(width: 48, alignment: .leading)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            
                            // Hourly Icon
                            let hourIcon = WidgetIconHelper.getIcon(for: hour.condition, isMinimalist: entry.weather.useMinimalistIcons)

                            if entry.weather.useMinimalistIcons ?? true {
                                Image(systemName: hourIcon)
                                    .font(.system(size: 20, weight: .light))
                                    .foregroundColor(.white)
                                    .symbolRenderingMode(.hierarchical)
                            } else {
                                Text(hourIcon)
                                    .font(.system(size: 20))
                            }
                            
                            Spacer(minLength: 0)
                            
                            Text(hour.temperature)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(10)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
        .containerBackground(for: .widget) {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: gradientColors),
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 180, height: 180)
                    .blur(radius: 60)
                    .offset(x: -50, y: -30)
                
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 140, height: 140)
                    .blur(radius: 55)
                    .offset(x: 60, y: 40)
            }
        }
    }
    
    var timeAgo: String {
        let interval = Date().timeIntervalSince(entry.weather.timestamp)
        let minutes = Int(interval / 60)
        
        if minutes < 1 {
            return "just now"
        } else if minutes < 60 {
            return "\(minutes)m ago"
        } else {
            let hours = minutes / 60
            return "\(hours)h ago"
        }
    }
    
    var gradientColors: [Color] {
        WeatherThemeHelper.gradientColors(for: entry.weather.condition, isDark: colorScheme == .dark)
    }
}

// MARK: - Widget Configuration

// MARK: - Custom Widget View

struct CustomWidgetView: View {
    let entry: WeatherEntry
    let config: CustomWidgetConfiguration
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Content based on Layout Style
            switch config.layoutStyle {
            case .standard:
                standardLayout
            case .split:
                splitLayout
            case .list:
                listLayout
            case .minimal:
                minimalLayout
            }
        }
        .containerBackground(for: .widget) {
            backgroundView
        }
    }
    
    // MARK: - Layouts (Duplicated from Preview for now, ideally shared in a helper)
    
    var standardLayout: some View {
        VStack(spacing: 0) {
            // Top Row
            HStack {
                metricView(for: .topLeft)
                Spacer()
                metricView(for: .topCenter)
                Spacer()
                metricView(for: .topRight)
            }
            .padding(.top, 12)
            .padding(.horizontal, 14)
            
            Spacer()
            
            // Middle Row
            HStack {
                metricView(for: .middleLeft)
                Spacer()
                metricView(for: .center)
                Spacer()
                metricView(for: .middleRight)
            }
             .padding(.horizontal, 14)
             
            Spacer()
            
            // Bottom Row
            HStack {
                metricView(for: .bottomLeft)
                Spacer()
                metricView(for: .bottomCenter)
                Spacer()
                metricView(for: .bottomRight)
            }
            .padding(.bottom, 12)
            .padding(.horizontal, 14)
        }
    }
    
    var splitLayout: some View {
        HStack(spacing: 20) {
            // Left Column
            VStack {
                metricView(for: .topLeft)
                Spacer()
                metricView(for: .middleLeft)
                Spacer()
                metricView(for: .bottomLeft)
            }
            
            Divider().background(Color.white.opacity(0.3))
            
            // Right Column
            VStack {
                metricView(for: .topRight)
                Spacer()
                metricView(for: .middleRight)
                Spacer()
                metricView(for: .bottomRight)
            }
        }
        .padding(14)
    }
    
    var listLayout: some View {
        VStack(spacing: 12) {
            HStack { metricView(for: .topLeft); Spacer() }
            HStack { metricView(for: .topCenter); Spacer() }
            HStack { metricView(for: .topRight); Spacer() }
            HStack { metricView(for: .middleLeft); Spacer() }
            HStack { metricView(for: .middleRight); Spacer() }
            HStack { metricView(for: .bottomLeft); Spacer() }
            HStack { metricView(for: .bottomCenter); Spacer() }
            HStack { metricView(for: .bottomRight); Spacer() }
        }
        .padding(14)
    }
    
    var minimalLayout: some View {
        ZStack {
            metricView(for: .center)
        }
        .padding(14)
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        switch config.backgroundStyle {
        case .solid:
            if let custom = config.customColors.first {
                custom.color
            } else {
                Color.blue
            }
        case .gradient:
            if config.customColors.count >= 2 {
                LinearGradient(
                    colors: config.customColors.map { $0.color },
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                // Default Blue Gradient
                LinearGradient(
                    colors: [.blue, .cyan],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        case .blur:
            ReferenceBackgroundView(entry: entry)
                .overlay(.ultraThinMaterial)
        case .weatherMatch:
            LinearGradient(
                gradient: Gradient(colors: WeatherThemeHelper.gradientColors(for: entry.weather.condition, isDark: colorScheme == .dark)),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    // Helper to determine alignment based on position
    func alignment(for position: WidgetMetricPosition) -> HorizontalAlignment {
        switch position {
        case .topLeft, .middleLeft, .bottomLeft:
            return .leading
        case .topRight, .middleRight, .bottomRight:
            return .trailing
        default:
            return .center
        }
    }
    
    @ViewBuilder
    func metricView(for position: WidgetMetricPosition) -> some View {
        if let type = config.metrics[position] {
            let align = alignment(for: position)
            VStack(alignment: align, spacing: 2) {
                content(for: type, position: position)
            }
            .foregroundColor(.white)
        } else {
            Color.clear.frame(width: 10, height: 10)
        }
    }
    
    @ViewBuilder
    func content(for type: WidgetMetricType, position: WidgetMetricPosition) -> some View {
        let align = alignment(for: position)
        
        switch type {
        case .temperature:
            if position == .center {
                Text(entry.weather.temperature)
                    .font(font(size: 38, weight: .bold))
                    .minimumScaleFactor(0.7)
            } else {
                VStack(alignment: align, spacing: 1) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 10))
                    Text(entry.weather.temperature)
                        .font(font(size: 12, weight: .bold))
                }
            }
            
        case .condition:
            if position == .center {
                let isMin = config.iconStyle == .minimalist
                let icon = WidgetIconHelper.getIcon(for: entry.weather.condition, isMinimalist: isMin)
                if isMin {
                    Image(systemName: icon)
                        .font(.system(size: 40))
                        .symbolRenderingMode(.hierarchical)
                } else {
                    Text(icon)
                        .font(.system(size: 40))
                }
            } else {
                let isMin = config.iconStyle == .minimalist
                let icon = WidgetIconHelper.getIcon(for: entry.weather.condition, isMinimalist: isMin)
                if isMin {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .symbolRenderingMode(.hierarchical)
                } else {
                    Text(icon)
                        .font(.system(size: 20))
                }
            }
            
        case .uvIndex:
            metricStack(icon: "sun.max.fill", value: "\(entry.weather.uvIndex ?? 0)", label: "UV", alignment: align)
            
        case .wind:
            metricStack(icon: "wind", value: entry.weather.windSpeed ?? "--", label: "Wind", alignment: align)
            
        case .humidity:
            metricStack(icon: "humidity.fill", value: entry.weather.humidity ?? "--", label: "", alignment: align)
            
        case .visibility:
             metricStack(icon: "eye.fill", value: entry.weather.visibility?.components(separatedBy: " ").first ?? "--", label: "km", alignment: align)
            
        case .feelsLike:
             // Need to add feels like to data model in future, using temp for now as placeholder or skipping
             metricStack(icon: "figure.stand", value: entry.weather.temperature, label: "Feels", alignment: align)
            
        case .precipChance:
            metricStack(icon: "umbrella.fill", value: entry.weather.rainChance ?? "0%", label: "", alignment: align)

        case .rainAmount:
            let amountComponents = (entry.weather.rainAmount ?? "0.0 mm").split(separator: " ", maxSplits: 1).map(String.init)
            metricStack(
                icon: "drop.fill",
                value: amountComponents.first ?? "--",
                label: amountComponents.count > 1 ? amountComponents[1] : "",
                alignment: align
            )
            
        case .pressure:
             metricStack(icon: "barometer", value: entry.weather.pressure?.components(separatedBy: " ").first ?? "--", label: "", alignment: align)
            
        case .highLow:
            VStack(alignment: align, spacing: 0) {
                Text("H:\(entry.weather.highTemp?.replacingOccurrences(of: "°", with: "") ?? "-")")
                Text("L:\(entry.weather.lowTemp?.replacingOccurrences(of: "°", with: "") ?? "-")")
            }
            .font(font(size: 10, weight: .bold))
            
        case .dailyForecast:
            if config.widgetSize == .small {
                // Compact view for small slots
                VStack(alignment: align, spacing: 2) {
                    Text("Today").font(font(size: 10, weight: .bold))
                    Image(systemName: "sun.max.fill")
                    Text(entry.weather.temperature).font(font(size: 10, weight: .bold))
                }
            } else if position == .center || position == .middleLeft || position == .middleRight {
                // Expanded view for larger slots - REAL DATA
                HStack(spacing: 8) {
                    ForEach(Array(entry.weather.dailyForecast.prefix(3)), id: \.dayName) { day in
                         DayForecastView(
                            day: day.dayName.prefix(3).description,
                            icon: WidgetIconHelper.getIcon(for: day.condition, isMinimalist: true),
                            temp: day.highTemp.replacingOccurrences(of: "°", with: "") + "°"
                        )
                    }
                }
            } else {
                Image(systemName: "calendar")
            }

        case .aqi:
            if position == .center {
                VStack(spacing: 0) {
                    Text("45")
                        .font(font(size: 28, weight: .heavy))
                    Text("Good")
                        .font(font(size: 10, weight: .medium))
                        .foregroundColor(.green)
                }
                .padding(8)
                .background(Color.black.opacity(0.2))
                .cornerRadius(8)
            } else {
                metricStack(icon: "aqi.low", value: "45", label: "AQI", alignment: align)
            }
            
        case .temperatureChart:
            if position == .center || position == .middleLeft || position == .middleRight {
                ChartMetricView(entry: entry, height: 40)
            } else {
                Image(systemName: "chart.xyaxis.line")
            }
        }
    }
    
    func metricStack(icon: String, value: String, label: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Image(systemName: icon)
                .font(font(size: 12, weight: .regular))
            Text(value)
                .font(font(size: 12, weight: .bold))
                .lineLimit(1)
            if !label.isEmpty {
                Text(label)
                .font(font(size: 8, weight: .medium))
                .opacity(0.8)
            }
        }
    }
    
    func font(size: CGFloat, weight: Font.Weight) -> Font {
        switch config.fontStyle {
        case .system: return .system(size: size, weight: weight)
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        case .serif: return .system(size: size, weight: weight, design: .serif)
        case .monospaced: return .system(size: size, weight: weight, design: .monospaced)
        }
    }
    
    @ViewBuilder
    func DayForecastView(day: String, icon: String, temp: String) -> some View {
        VStack(spacing: 2) {
            Text(day).font(font(size: 10, weight: .medium)).opacity(0.8)
            Image(systemName: icon).font(font(size: 12, weight: .regular))
            Text(temp).font(font(size: 11, weight: .bold))
        }
    }
}

// Helper for blur background
struct ReferenceBackgroundView: View {
    let entry: WeatherEntry
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        LinearGradient(
             gradient: Gradient(colors: WeatherThemeHelper.gradientColors(for: entry.weather.condition, isDark: colorScheme == .dark)),
             startPoint: .top,
             endPoint: .bottom
         )
    }
}

struct BreezyWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family
    
    // Load config helper
    var customConfig: CustomWidgetConfiguration? {
        WidgetConfigLoader.load()
    }
    
    var body: some View {
        // Check for custom config availability
        if let config = customConfig {
             // We could be smarter here and check if the config size matches the current family,
             // but for flexibility, we'll try to render the custom view if it's one of the main sizes.
             // In a polished app, you might have separate configs for different sizes.
             // Here, we assume the user's "Widget Studio" config applies to whichever size they add.
             
             switch family {
             #if os(iOS)
             case .systemSmall, .systemMedium, .systemLarge:
                 CustomWidgetView(entry: entry, config: config)
             #endif
             default:
                 // Fallback for accessories
                 standardWidgetView
             }
        } else {
            standardWidgetView
        }
    }
    
    @ViewBuilder
    var standardWidgetView: some View {
        switch family {
            #if os(iOS)
            case .systemSmall:
                SmallWidgetView(entry: entry)
            case .systemMedium:
                MediumWidgetView(entry: entry)
            case .systemLarge:
                LargeWidgetView(entry: entry)
            #endif
            case .accessoryRectangular:
                AccessoryRectangularView(entry: entry)
            case .accessoryCircular:
                AccessoryCircularView(entry: entry)
            case .accessoryInline:
                AccessoryInlineView(entry: entry)
            default:
                #if os(iOS)
                SmallWidgetView(entry: entry)
                #else
                AccessoryRectangularView(entry: entry)
                #endif
            }
    }
}

// MARK: - Main Widget Bundle

@main
struct BreezyWidgetBundle: WidgetBundle {
    var body: some Widget {
        BreezyCompactWidget()
        BreezyDetailedWidget()
        BreezyForecastWidget()
        BreezyCircularUVWidget()
        BreezyInlineWidget()
        BreezyCircularTempWidget()
        BreezyCircularRainWidget()
        BreezyCircularWindWidget() // Ensure Wind is also available
        BreezySunLockWidget() // Sun Lock Screen
        BreezyMoonLockWidget() // Moon Lock Screen
        #if os(iOS)
        BreezyUVWidget() // New Graph Widget
        BreezyWindWidget() // New Wind Widget
        BreezySunWidget() // New Astronomy
        BreezyMoonWidget() // New Astronomy
        #endif
        BreezyWeatherWidget() // Custom Widget moved to end
    }
}

// MARK: - UV Widget (System Small)

#if os(iOS)
struct BreezyUVWidget: Widget {
    let kind: String = "BreezyUVWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            BreezyUVWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("UV Index")
        .description("Track UV levels throughout the day.")
        .supportedFamilies([.systemSmall])
    }
}

struct BreezyUVWidgetEntryView: View {
    var entry: WeatherEntry
    @Environment(\.colorScheme) var colorScheme
    
    
    
    var body: some View {
        let uv = entry.weather.uvIndex ?? 0
        
        VStack(spacing: 4) {
             // Header
            HStack(spacing: 4) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)
                Text("UV Index")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.top, 4)
            
            Spacer()
            
            // Value + Description (Stacked to avoid truncation)
            VStack(spacing: 0) {
                Text("\(uv)")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.1), radius: 2)
                
                Text(uvDescription(uv))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
            
            Spacer()
            
            // UV Graph simulation
            UVGraphView(currentUV: uv)
                .frame(height: 32)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .containerBackground(for: .widget) {
            LinearGradient(
                gradient: Gradient(colors: WeatherThemeHelper.gradientColors(for: entry.weather.condition, isDark: colorScheme == .dark)),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    func uvDescription(_ uv: Int) -> String {
        switch uv {
        case 0...2: return "Low"
        case 3...5: return "Moderate"
        case 6...7: return "High"
        case 8...10: return "Very High"
        default: return "Extreme"
        }
    }
}

struct UVGraphView: View {
    let currentUV: Int
    
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            
            // X-axis: 6 AM to 8 PM (14 hours)
            let startHour = 6.0
            let endHour = 20.0
            let totalHours = endHour - startHour
            
            // Current Time Progress
            let calendar = Calendar.current
            let hour = Double(calendar.component(.hour, from: Date()))
            let minute = Double(calendar.component(.minute, from: Date()))
            let currentDecimalHour = hour + (minute / 60.0)
            
            // Clamped progress (0.0 to 1.0)
            let rawProgress = (currentDecimalHour - startHour) / totalHours
            let progress = max(0.0, min(1.0, rawProgress))
            
            ZStack {
                // 1. The Full Day Curve (Static Reference)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: height))
                    
                    for x in stride(from: 0, through: width, by: 2) {
                        let relX = x / width
                        // Parabolic curve peaking at 0.5 (1 PM approx)
                        // y = 4 * x * (1 - x) is a simple parabola 0 -> 1 -> 0
                        let curveY = 4 * relX * (1.0 - relX)
                        let y = height - (curveY * height * 0.8) // Height scaling
                        
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [.yellow.opacity(0.2), .orange.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                
                // 2. Stroke for the curve
                Path { path in
                    path.move(to: CGPoint(x: 0, y: height))
                    for x in stride(from: 0, through: width, by: 2) {
                        let relX = x / width
                        let curveY = 4 * relX * (1.0 - relX)
                        let y = height - (curveY * height * 0.8)
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
                
                // 3. Current Position Indicator
                let currentX = width * progress
                let currentRelX = progress
                let currentCurveY = 4 * currentRelX * (1.0 - currentRelX)
                let currentY = height - (currentCurveY * height * 0.8)
                
                // Active Path (filled up to current time) -> Optional, maybe just the dot is cleaner?
                // Let's just do the Dot and a solid line for the "past"
                
                Path { path in
                    path.move(to: CGPoint(x: 0, y: height))
                    for x in stride(from: 0, through: currentX, by: 2) {
                        let relX = x / width
                        let curveY = 4 * relX * (1.0 - relX)
                        let y = height - (curveY * height * 0.8)
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                .stroke(
                    LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing),
                    lineWidth: 3
                )
                
                // The Dot
                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .position(x: currentX, y: currentY)
                    .shadow(color: .black.opacity(0.2), radius: 2)
            }
        }
    }
}
#endif

#if os(iOS)
struct BreezyWindWidget: Widget {
    let kind: String = "BreezyWindWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            BreezyWindWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Wind Speed")
        .description("Monitor wind conditions.")
        .supportedFamilies([.systemSmall])
    }
}

struct BreezyWindWidgetEntryView: View {
    var entry: WeatherEntry
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        let windString = entry.weather.windSpeed ?? "0 mph"
        let windSpeed = Double(windString.filter { "0123456789.".contains($0) }) ?? 0
        
        VStack(spacing: 4) {
            // Header
             HStack(spacing: 4) {
                Image(systemName: "wind")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.8))
                Text("Wind")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.top, 4)
            
            Spacer()
            
            // Centered Gauge with Value Inside
            ZStack {
                // Background Ring
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 8)
                    .frame(width: 80, height: 80)
                
                // Active Ring
                Circle()
                    .trim(from: 0, to: min(CGFloat(windSpeed) / 40.0, 1.0))
                    .stroke(
                        LinearGradient(colors: [.cyan.opacity(0.8), .blue], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                
                // Value Inside
                VStack(spacing: 0) {
                    Text("\(Int(windSpeed))")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    
                    // Extract unit from string (e.g. "24 km/h" -> "km/h")
                    let unit = windString.components(separatedBy: " ").last ?? "mph"
                    Text(unit)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            
            Spacer()
        }
        .padding(12)
        .containerBackground(for: .widget) {
            LinearGradient(
                gradient: Gradient(colors: WeatherThemeHelper.gradientColors(for: entry.weather.condition, isDark: colorScheme == .dark)),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
#endif

// MARK: - Standard Weather Widget

struct BreezyWeatherWidget: Widget {
    let kind: String = "BreezyWeatherWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            BreezyWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Weather")
        .description("Current weather with hourly forecast.")
        .supportedFamilies(supportedFamilies)
    }
    
    private var supportedFamilies: [WidgetFamily] {
        #if os(iOS)
        return [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular, .accessoryInline]
        #else
        return [.accessoryRectangular, .accessoryCircular, .accessoryInline]
        #endif
    }
}

// MARK: - Compact Widget (Minimal Info)

struct BreezyCompactWidget: Widget {
    let kind: String = "BreezyCompactWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            BreezyCompactWidgetView(entry: entry)
        }
        .configurationDisplayName("Weather - Compact")
        .description("Minimal weather display with just the essentials.")
        .supportedFamilies(supportedFamilies)
    }
    
    private var supportedFamilies: [WidgetFamily] {
        #if os(iOS)
        return [.systemSmall, .systemMedium]
        #else
        return []
        #endif
    }
}

// MARK: - Detailed Widget (More Info)

struct BreezyDetailedWidget: Widget {
    let kind: String = "BreezyDetailedWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            BreezyDetailedWidgetView(entry: entry)
        }
        .configurationDisplayName("Weather - Detailed")
        .description("Comprehensive weather information with extended forecast.")
        .supportedFamilies(supportedFamilies)
    }
    
    private var supportedFamilies: [WidgetFamily] {
        #if os(iOS)
        return [.systemMedium, .systemLarge]
        #else
        return []
        #endif
    }
}

// MARK: - Lock Screen Widget Views (iOS 16+)

struct AccessoryRectangularView: View {
    let entry: WeatherEntry
    
    private var useMinimalist: Bool {
        entry.weather.useMinimalistIcons ?? true
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // Icon
            if useMinimalist {
                Image(systemName: WidgetIconHelper.getIcon(for: entry.weather.condition, isMinimalist: true))
                    .font(.system(size: 16, weight: .medium))
                    .widgetAccentable()
            } else {
                Text(entry.weather.emoji)
                    .font(.system(size: 16))
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.weather.city)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                
                Text(entry.weather.temperature)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
            }
            
            Spacer()
            
            if let high = entry.weather.highTemp, let low = entry.weather.lowTemp {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("H:\(cleanTemp(high))")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Text("L:\(cleanTemp(low))")
                        .font(.system(size: 10, weight: .regular))
                        .lineLimit(1)
                        .opacity(0.75)
                }
            }
        }
        .widgetAccentable()
        .containerBackground(for: .widget) {
            Color.clear
        }
    }
    
    private func cleanTemp(_ temp: String) -> String {
        temp.replacingOccurrences(of: "°", with: "")
            .replacingOccurrences(of: "F", with: "")
            .replacingOccurrences(of: "C", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

struct AccessoryCircularView: View {
    let entry: WeatherEntry
    
    private var useMinimalist: Bool {
        entry.weather.useMinimalistIcons ?? true
    }
    
    private var gaugeValue: Double {
        // Extract numeric values from temperature strings (e.g., "22°C" -> 22.0)
        guard let currentTemp = extractTemperature(from: entry.weather.temperature),
              let highTemp = entry.weather.highTemp.flatMap({ extractTemperature(from: $0) }),
              let lowTemp = entry.weather.lowTemp.flatMap({ extractTemperature(from: $0) }) else {
            return 0.5 // Default to middle if we can't parse
        }
        
        // Calculate position between min and max (0.0 = min, 1.0 = max)
        let range = highTemp - lowTemp
        guard range > 0 else { return 0.5 } // Avoid division by zero
        
        let position = (currentTemp - lowTemp) / range
        return max(0.0, min(1.0, position)) // Clamp between 0 and 1
    }
    
    private func extractTemperature(from string: String) -> Double? {
        // Remove all non-numeric characters except minus sign and decimal point
        let cleaned = string.replacingOccurrences(of: "[^0-9.-]", with: "", options: .regularExpression)
        return Double(cleaned)
    }
    
    var body: some View {
        Gauge(value: gaugeValue) {
            if useMinimalist {
                Image(systemName: WidgetIconHelper.getIcon(for: entry.weather.condition, isMinimalist: true))
                    .font(.system(size: 18, weight: .medium))
            } else {
                Text(entry.weather.emoji)
                    .font(.system(size: 18))
            }
        } currentValueLabel: {
            Text(entry.weather.temperature)
                .font(.system(size: 10, weight: .bold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .gaugeStyle(.accessoryCircular)
        .containerBackground(for: .widget) {
            Color.clear
        }
    }
}

struct AccessoryInlineView: View {
    let entry: WeatherEntry
    
    private var useMinimalist: Bool {
        entry.weather.useMinimalistIcons ?? true
    }
    
    var body: some View {
        Label {
            Text("\(entry.weather.city): \(entry.weather.temperature)")
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        } icon: {
            if useMinimalist {
                Image(systemName: WidgetIconHelper.getIcon(for: entry.weather.condition, isMinimalist: true))
                    .font(.system(size: 11, weight: .medium))
            } else {
                Text(entry.weather.emoji)
                    .font(.system(size: 11))
            }
        }
        .widgetAccentable()
        .containerBackground(for: .widget) {
            Color.clear
        }
    }
}


// MARK: - Compact Widget Views

struct BreezyCompactWidgetView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        #if os(iOS)
        case .systemSmall:
            CompactSmallWidgetView(entry: entry)
        case .systemMedium:
            CompactMediumWidgetView(entry: entry)
        #endif
        default:
            #if os(iOS)
            CompactSmallWidgetView(entry: entry)
            #else
            AccessoryRectangularView(entry: entry)
            #endif
        }
    }
}

struct CompactSmallWidgetView: View {
    let entry: WeatherEntry
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 8) {
            let icon = WidgetIconHelper.getIcon(for: entry.weather.condition, isMinimalist: entry.weather.useMinimalistIcons)
            
            if entry.weather.useMinimalistIcons ?? true {
                Image(systemName: icon)
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(.white)
                    .symbolRenderingMode(.hierarchical)
            } else {
                Text(icon)
                    .font(.system(size: 36))
            }
            
            Text(entry.weather.temperature)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) {
            LinearGradient(
                gradient: Gradient(colors: gradientColors),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    var gradientColors: [Color] {
        WeatherThemeHelper.gradientColors(for: entry.weather.condition, isDark: colorScheme == .dark)
    }
}

struct CompactMediumWidgetView: View {
    let entry: WeatherEntry
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                let icon = WidgetIconHelper.getIcon(for: entry.weather.condition, isMinimalist: entry.weather.useMinimalistIcons)
                
                if entry.weather.useMinimalistIcons ?? true {
                    Image(systemName: icon)
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(.white)
                        .symbolRenderingMode(.hierarchical)
                } else {
                    Text(icon)
                        .font(.system(size: 32))
                }
                
                Text(entry.weather.temperature)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(entry.weather.city)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(entry.weather.condition)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                
                if let high = entry.weather.highTemp, let low = entry.weather.lowTemp {
                    HStack(spacing: 4) {
                        Text("H:\(high)")
                            .font(.system(size: 11, weight: .medium))
                        Text("L:\(low)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.75))
                }
            }
        }
        .padding(16)
        .containerBackground(for: .widget) {
            LinearGradient(
                gradient: Gradient(colors: gradientColors),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    var gradientColors: [Color] {
        WeatherThemeHelper.gradientColors(for: entry.weather.condition, isDark: colorScheme == .dark)
    }
}

// MARK: - Detailed Widget Views

struct BreezyDetailedWidgetView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        #if os(iOS)
        case .systemMedium:
            DetailedMediumWidgetView(entry: entry)
        case .systemLarge:
            DetailedLargeWidgetView(entry: entry)
        #endif
        default:
            #if os(iOS)
            DetailedMediumWidgetView(entry: entry)
            #else
            AccessoryRectangularView(entry: entry)
            #endif
        }
    }
}

struct DetailedMediumWidgetView: View {
    let entry: WeatherEntry
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.weather.city)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(entry.weather.condition)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                }
                Spacer()
                
                Text(entry.weather.temperature)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Today")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                
                HStack(spacing: 8) {
                    ForEach(entry.nextThreeHours, id: \.time) { hour in
                        VStack(spacing: 4) {
                            Text(hour.time)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                            
                            let hourIcon = WidgetIconHelper.getIcon(for: hour.condition, isMinimalist: entry.weather.useMinimalistIcons)
                            
                            if entry.weather.useMinimalistIcons ?? true {
                                Image(systemName: hourIcon)
                                    .font(.system(size: 16, weight: .light))
                                    .foregroundColor(.white)
                            } else {
                                Text(hourIcon)
                                    .font(.system(size: 16))
                            }
                            
                            Text(hour.temperature)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(16)
        .containerBackground(for: .widget) {
            LinearGradient(
                gradient: Gradient(colors: gradientColors),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    var gradientColors: [Color] {
        WeatherThemeHelper.gradientColors(for: entry.weather.condition, isDark: colorScheme == .dark)
    }
}

struct DetailedLargeWidgetView: View {
    let entry: WeatherEntry
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.weather.city)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(entry.weather.condition)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                    
                    if let high = entry.weather.highTemp, let low = entry.weather.lowTemp {
                        HStack(spacing: 6) {
                            Text("H:\(high)")
                                .font(.system(size: 13, weight: .semibold))
                            Text("•")
                                .foregroundColor(.white.opacity(0.5))
                            Text("L:\(low)")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white.opacity(0.85))
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    let icon = WidgetIconHelper.getIcon(for: entry.weather.condition, isMinimalist: entry.weather.useMinimalistIcons)
                    
                    if entry.weather.useMinimalistIcons ?? true {
                        Image(systemName: icon)
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(.white)
                            .symbolRenderingMode(.hierarchical)
                    } else {
                        Text(icon)
                            .font(.system(size: 48))
                    }
                    
                    Text(entry.weather.temperature)
                        .font(.system(size: 42, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.3))
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Hourly Forecast")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                
                VStack(spacing: 8) {
                    ForEach(entry.nextThreeHours, id: \.time) { hour in
                        HStack {
                            Text(hour.time)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .frame(width: 50, alignment: .leading)
                            
                            let hourIcon = WidgetIconHelper.getIcon(for: hour.condition, isMinimalist: entry.weather.useMinimalistIcons)
                            
                            if entry.weather.useMinimalistIcons ?? true {
                                Image(systemName: hourIcon)
                                    .font(.system(size: 20, weight: .light))
                                    .foregroundColor(.white)
                            } else {
                                Text(hourIcon)
                                    .font(.system(size: 20))
                            }
                            
                            Spacer()
                            
                            Text(hour.temperature)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
        .padding(18)
        .containerBackground(for: .widget) {
            LinearGradient(
                gradient: Gradient(colors: gradientColors),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    var gradientColors: [Color] {
        WeatherThemeHelper.gradientColors(for: entry.weather.condition, isDark: colorScheme == .dark)
    }
}

// MARK: - Circular UV Widget
struct BreezyCircularUVWidget: Widget {
    let kind: String = "BreezyCircularUVWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            AccessoryUVLockView(entry: entry)
        }
        .configurationDisplayName("UV Index")
        .description("Current UV exposure levels.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct AccessoryUVLockView: View {
    let entry: WeatherEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularUVView(entry: entry)
        case .accessoryRectangular:
            RectangularUVView(entry: entry)
        default:
            CircularUVView(entry: entry)
        }
    }
}

struct CircularUVView: View {
    let entry: WeatherEntry
    
    var body: some View {
        let uv = Double(entry.weather.uvIndex ?? 0)
        
        Gauge(value: uv, in: 0...12) {
            Image(systemName: "sun.max.fill")
                .symbolRenderingMode(.hierarchical)
        } currentValueLabel: {
            Text("\(Int(uv))")
        } minimumValueLabel: {
            Text("0")
                .font(.system(size: 8))
        } maximumValueLabel: {
            Text("12+")
                .font(.system(size: 8))
        }
        .gaugeStyle(.accessoryCircular)
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct RectangularUVView: View {
    let entry: WeatherEntry
    
    var body: some View {
        let uv = entry.weather.uvIndex ?? 0
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(uv)")
                    .font(.system(size: 24, weight: .semibold))
                Text(uvDescription(for: uv))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Text("UV INDEX")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
            
            Gauge(value: Double(uv), in: 0...12) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinear)
            .tint(uvTint(for: uv))
        }
        .containerBackground(for: .widget) { Color.clear }
    }
    
    func uvDescription(for uv: Int) -> String {
        if uv <= 2 { return "Low" }
        if uv <= 5 { return "Mod" }
        if uv <= 7 { return "High" }
        if uv <= 10 { return "Very High" }
        return "Extreme"
    }
    
    func uvTint(for uv: Int) -> Color {
        if uv <= 2 { return .green }
        if uv <= 5 { return .yellow }
        if uv <= 7 { return .orange }
        if uv <= 10 { return .red }
        return .purple
    }
}

// MARK: - New Lock Screen Widgets

// 1. Inline Widget (Text above time)
struct BreezyInlineWidget: Widget {
    let kind: String = "BreezyInlineWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            AccessoryInlineView(entry: entry)
        }
        .configurationDisplayName("Weather Condition")
        .description("Current weather conditions and temperature.")
        .supportedFamilies([.accessoryInline])
    }
}



// 2. Circular Temp Gradient Widget
struct BreezyCircularTempWidget: Widget {
    let kind: String = "BreezyCircularTempWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            AccessoryTempLockView(entry: entry)
        }
        .configurationDisplayName("Temperature")
        .description("Current temperature with high/low range.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct AccessoryTempLockView: View {
    let entry: WeatherEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularTempView(entry: entry)
        case .accessoryRectangular:
            RectangularTempView(entry: entry)
        default:
            CircularTempView(entry: entry)
        }
    }
}

struct CircularTempView: View {
    let entry: WeatherEntry
    
    var body: some View {
        Gauge(value: currentTempVal, in: minTemp...maxTemp) {
            Image(systemName: "thermometer")
        } currentValueLabel: {
            Text(entry.weather.temperature)
        } minimumValueLabel: {
            Text(entry.weather.lowTemp?.replacingOccurrences(of: "°", with: "") ?? "")
                .font(.system(size: 8))
        } maximumValueLabel: {
            Text(entry.weather.highTemp?.replacingOccurrences(of: "°", with: "") ?? "")
                .font(.system(size: 8))
        }
        .gaugeStyle(.accessoryCircular)
        .containerBackground(for: .widget) { Color.clear }
    }
    
    var currentTempVal: Double {
        extractNumber(from: entry.weather.temperature) ?? 20
    }
    var minTemp: Double {
        extractNumber(from: entry.weather.lowTemp ?? "") ?? (currentTempVal - 5)
    }
    var maxTemp: Double {
        extractNumber(from: entry.weather.highTemp ?? "") ?? (currentTempVal + 5)
    }
    
    func extractNumber(from str: String) -> Double? {
        Double(str.replacingOccurrences(of: "[^0-9.-]", with: "", options: .regularExpression))
    }
}

struct RectangularTempView: View {
    let entry: WeatherEntry
    
    var body: some View {
        let current = extractNumber(from: entry.weather.temperature) ?? 0
        let low = extractNumber(from: entry.weather.lowTemp ?? "0") ?? (current - 5)
        let high = extractNumber(from: entry.weather.highTemp ?? "0") ?? (current + 5)
        
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.weather.temperature)
                    .font(.system(size: 24, weight: .semibold))
                
                Text("H:\(entry.weather.highTemp ?? "--") L:\(entry.weather.lowTemp ?? "--")")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                Spacer()
                Text("TEMP")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
            
            Gauge(value: current, in: low...high) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinear)
        }
        .containerBackground(for: .widget) { Color.clear }
    }
    
    func extractNumber(from str: String) -> Double? {
        Double(str.replacingOccurrences(of: "[^0-9.-]", with: "", options: .regularExpression))
    }
}

// 3. Circular Rain Widget
struct BreezyCircularRainWidget: Widget {
    let kind: String = "BreezyCircularRainWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            AccessoryRainLockView(entry: entry)
        }
        .configurationDisplayName("Rain Chance")
        .description("Chance of precipitation.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct AccessoryRainLockView: View {
    let entry: WeatherEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularRainView(entry: entry)
        case .accessoryRectangular:
            RectangularRainView(entry: entry)
        default:
            CircularRainView(entry: entry)
        }
    }
}

struct CircularRainView: View {
    let entry: WeatherEntry
    
    var body: some View {
        let chance = extractNumber(from: entry.weather.rainChance ?? "0%") ?? 0
        
        Gauge(value: chance, in: 0...100) {
            Image(systemName: "cloud.rain.fill")
        } currentValueLabel: {
            Text("\(Int(chance))%")
        }
        .gaugeStyle(.accessoryCircular)
        .containerBackground(for: .widget) { Color.clear }
    }
    
    func extractNumber(from str: String) -> Double? {
        Double(str.replacingOccurrences(of: "[^0-9.-]", with: "", options: .regularExpression))
    }
}

struct RectangularRainView: View {
    let entry: WeatherEntry
    
    var body: some View {
        let chance = extractNumber(from: entry.weather.rainChance ?? "0%") ?? 0
        
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.weather.rainChance ?? "0%")
                    .font(.system(size: 24, weight: .semibold))
                
                Text("Humidity: \(entry.weather.humidity ?? "--")")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                Spacer()
                Text("RAIN")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
            
            Gauge(value: chance, in: 0...100) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinear)
            .tint(.blue)
        }
        .containerBackground(for: .widget) { Color.clear }
    }
    
    func extractNumber(from str: String) -> Double? {
        Double(str.replacingOccurrences(of: "[^0-9.-]", with: "", options: .regularExpression))
    }
}

// 4. Circular Wind Widget
struct BreezyCircularWindWidget: Widget {
    let kind: String = "BreezyCircularWindWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            AccessoryWindLockView(entry: entry)
        }
        .configurationDisplayName("Wind")
        .description("Wind speed and direction.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct AccessoryWindLockView: View {
    let entry: WeatherEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .accessoryCircular:
            CircularWindView(entry: entry)
        case .accessoryRectangular:
            RectangularWindView(entry: entry)
        default:
            CircularWindView(entry: entry)
        }
    }
}

struct CircularWindView: View {
    let entry: WeatherEntry
    
    var body: some View {
        let speed = extractNumber(from: entry.weather.windSpeed ?? "0") ?? 0
        
        Gauge(value: speed, in: 0...50) {
            if let degrees = entry.weather.windDirectionDegrees {
                Image(systemName: "arrow.up")
                    .rotationEffect(.degrees(degrees + 180)) // Point IN direction of flow
                    .font(.system(size: 12, weight: .bold))
            } else {
                Image(systemName: "wind")
                    .font(.system(size: 14))
            }
        } currentValueLabel: {
            Text(entry.weather.windSpeed?.replacingOccurrences(of: " ", with: "") ?? "--")
                 .font(.system(size: 10, weight: .bold, design: .rounded))
                 .minimumScaleFactor(0.8)
        }
        .gaugeStyle(.accessoryCircular)
        .containerBackground(for: .widget) { Color.clear }
    }
    
    func extractNumber(from str: String) -> Double? {
        Double(str.replacingOccurrences(of: "[^0-9.-]", with: "", options: .regularExpression))
    }
}

struct RectangularWindView: View {
    let entry: WeatherEntry
    
    var body: some View {
        let speed = extractNumber(from: entry.weather.windSpeed ?? "0") ?? 0
        
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.weather.windSpeed ?? "--")
                    .font(.system(size: 24, weight: .semibold))
                
                Text(entry.weather.visibility ?? "--")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                Spacer()
                Text("WIND")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
            
            Gauge(value: speed, in: 0...50) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinear)
            .tint(.gray)
        }
        .containerBackground(for: .widget) { Color.clear }
    }
    
    func extractNumber(from str: String) -> Double? {
        Double(str.replacingOccurrences(of: "[^0-9.-]", with: "", options: .regularExpression))
    }
}

// MARK: - Astronomy Widgets

#if os(iOS)
// 1. Sun Widget
struct BreezySunWidget: Widget {
    let kind: String = "BreezySunWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            BreezySunWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Sunrise & Sunset")
        .description("Track the sun's position and daylight hours.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
#endif

struct BreezySunWidgetEntryView: View {
    let entry: WeatherEntry
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        switch family {
        case .systemSmall:
            SunSmallView(entry: entry)
        case .systemMedium:
            SunMediumView(entry: entry)
        default:
            SunSmallView(entry: entry)
        }
    }
}

struct SunSmallView: View {
    let entry: WeatherEntry
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 4) {
             // Header
            HStack(spacing: 4) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)
                Text("Sun")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.top, 4)
            
            Spacer()
            
            // Visualization
            SunPathView(sunrise: entry.weather.sunrise ?? Date(), sunset: entry.weather.sunset ?? Date(), currentTime: Date())
                .frame(height: 60)
                .padding(.horizontal, 8)
            
            // Text Info
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Rise")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Text(formatTime(entry.weather.sunrise ?? Date()))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Set")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Text(formatTime(entry.weather.sunset ?? Date()))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(.bottom, 4)
        }
        .padding(12)
        .containerBackground(for: .widget) {
            LinearGradient(
                gradient: Gradient(colors: WeatherThemeHelper.gradientColors(for: entry.weather.condition, isDark: colorScheme == .dark)),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct SunMediumView: View {
    let entry: WeatherEntry
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            // Left: Visualization
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                    Text("Sun Position")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                SunPathView(sunrise: entry.weather.sunrise ?? Date(), sunset: entry.weather.sunset ?? Date(), currentTime: Date())
                    .frame(height: 80)
            }
            .frame(maxWidth: .infinity)
            
            Divider().background(Color.white.opacity(0.2))
            
            // Right: Details
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Sunrise", systemImage: "sunrise.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    Text(formatTime(entry.weather.sunrise ?? Date()))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Label("Sunset", systemImage: "sunset.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    Text(formatTime(entry.weather.sunset ?? Date()))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // Daylight duration?
                if let rise = entry.weather.sunrise, let set = entry.weather.sunset {
                    let diff = set.timeIntervalSince(rise)
                    let hours = Int(diff) / 3600
                    let mins = (Int(diff) % 3600) / 60
                    
                    Text("\(hours)h \(mins)m Daylight")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top, 4)
                }
            }
            .frame(width: 100)
        }
        .padding(16)
        .containerBackground(for: .widget) {
            LinearGradient(
                gradient: Gradient(colors: WeatherThemeHelper.gradientColors(for: entry.weather.condition, isDark: colorScheme == .dark)),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#if os(iOS)
// 2. Moon Widget
struct BreezyMoonWidget: Widget {
    let kind: String = "BreezyMoonWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
             BreezyMoonWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Moon Phase")
        .description("Current moon phase and illumination.")
        .supportedFamilies([.systemSmall])
    }
}
#endif

struct BreezyMoonWidgetEntryView: View {
    let entry: WeatherEntry
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                Text("Moon")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.top, 4)
            
            Spacer()
            
            // Moon Visual
            Image(systemName: moonSymbol(for: entry.weather.moonPhase ?? ""))
                .font(.system(size: 42))
                .foregroundColor(.white)
                .shadow(color: .white.opacity(0.3), radius: 8)
            
            Spacer()
            
            VStack(spacing: 2) {
                Text(entry.weather.moonPhase ?? "Waxing Crescent")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                if let illumination = entry.weather.moonIllumination {
                    Text("\(Int(illumination * 100))% Illumination")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding(12)
        .containerBackground(for: .widget) {
            LinearGradient(
                gradient: Gradient(colors: WeatherThemeHelper.gradientColors(for: entry.weather.condition, isDark: colorScheme == .dark)),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    func moonSymbol(for phase: String) -> String {
        let p = phase.lowercased()
        if p.contains("new") { return "moonphase.new.moon" }
        if p.contains("waxing crescent") { return "moonphase.waxing.crescent" }
        if p.contains("first quarter") { return "moonphase.first.quarter" }
        if p.contains("waxing gibbous") { return "moonphase.waxing.gibbous" }
        if p.contains("full") { return "moonphase.full.moon" }
        if p.contains("waning gibbous") { return "moonphase.waning.gibbous" }
        if p.contains("last quarter") { return "moonphase.last.quarter" }
        if p.contains("waning crescent") { return "moonphase.waning.crescent" }
        return "moon.stars.fill"
    }
}

// 3. Lock Screen Sun Widget
struct BreezySunLockWidget: Widget {
    let kind: String = "BreezySunLockWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            BreezySunLockWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Sun Events")
        .description("Sunrise and sunset times.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct BreezySunLockWidgetEntryView: View {
    let entry: WeatherEntry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .accessoryCircular:
            SunLockCircularView(entry: entry)
        case .accessoryRectangular:
            SunLockRectangularView(entry: entry)
        default:
            SunLockCircularView(entry: entry)
        }
    }
}

struct SunLockCircularView: View {
    let entry: WeatherEntry
    
    var body: some View {
        // Show next event (Rise or Set)
        let now = Date()
        let sunrise = entry.weather.sunrise ?? now
        let sunset = entry.weather.sunset ?? now
        
        let isDay = now > sunrise && now < sunset
        let nextEventTime = isDay ? sunset : sunrise
        let icon = isDay ? "sunset.fill" : "sunrise.fill"
        
        VStack(spacing: 1) {
            Image(systemName: icon)
                .font(.system(size: 14))
            Text(formatTime(nextEventTime))
                .font(.system(size: 10, weight: .semibold))
        }
        .containerBackground(for: .widget) { Color.clear }
    }
    
    func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct SunLockRectangularView: View {
    let entry: WeatherEntry
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "sunrise.fill")
                        .font(.system(size: 12))
                    Text(formatTime(entry.weather.sunrise ?? Date()))
                        .font(.system(size: 14, weight: .semibold))
                }
                HStack(spacing: 4) {
                    Image(systemName: "sunset.fill")
                         .font(.system(size: 12))
                    Text(formatTime(entry.weather.sunset ?? Date()))
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            Spacer()
        }
        .containerBackground(for: .widget) { Color.clear }
    }
    
    func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// 4. Lock Screen Moon Widget
struct BreezyMoonLockWidget: Widget {
    let kind: String = "BreezyMoonLockWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            BreezyMoonLockWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Moon Phase")
        .description("Current moon phase.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct BreezyMoonLockWidgetEntryView: View {
    let entry: WeatherEntry
    
    var body: some View {
        // Just the icon for circular lock screen
        let symbol = moonSymbol(for: entry.weather.moonPhase ?? "")
        
        VStack {
            Image(systemName: symbol)
                .font(.system(size: 24))
        }
        .containerBackground(for: .widget) { Color.clear }
    }
    
    func moonSymbol(for phase: String) -> String {
        let p = phase.lowercased()
        if p.contains("new") { return "moonphase.new.moon" }
        if p.contains("waxing crescent") { return "moonphase.waxing.crescent" }
        if p.contains("first quarter") { return "moonphase.first.quarter" }
        if p.contains("waxing gibbous") { return "moonphase.waxing.gibbous" }
        if p.contains("full") { return "moonphase.full.moon" }
        if p.contains("waning gibbous") { return "moonphase.waning.gibbous" }
        if p.contains("last quarter") { return "moonphase.last.quarter" }
        if p.contains("waning crescent") { return "moonphase.waning.crescent" }
        return "moon.stars.fill"
    }
}

// MARK: - Astronomy Components

struct SunPathView: View {
    let sunrise: Date
    let sunset: Date
    let currentTime: Date
    
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            
            // Horizon
            Path { path in
                path.move(to: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: w, y: h))
            }
            .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            
            let radius = min(w / 2, h - 10)
            let center = CGPoint(x: w/2, y: h)
            
            // Full Arc (Dashed Background)
            SunArc(radius: radius, center: center)
                .stroke(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
            
            // Progress
            let totalDuration = sunset.timeIntervalSince(sunrise)
            let currentElapsed = currentTime.timeIntervalSince(sunrise)
            
            if totalDuration > 0 {
                let checkProgress = currentElapsed / totalDuration
                let progress = max(0.0, min(1.0, checkProgress))
                
                // Active Arc (Trimmed)
                SunArc(radius: radius, center: center)
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                
                // Sun Icon Position
                let angle = 180 - (180 * progress)
                let radians = angle * .pi / 180
                
                let sunX = center.x + radius * cos(CGFloat(radians))
                let sunY = center.y - radius * sin(CGFloat(radians))
                
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 12, height: 12)
                    .position(x: sunX, y: sunY)
                    .shadow(color: .orange.opacity(0.5), radius: 3)
            }
        }
    }
}

struct SunArc: Shape {
    let radius: CGFloat
    let center: CGPoint
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: center.x - radius, y: center.y))
        path.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        return path
    }
}

// MARK: - Chart Metric View
struct ChartMetricView: View {
    let entry: WeatherEntry
    let height: CGFloat
    
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let padding: CGFloat = 12
            let viewHeight = proxy.size.height - (padding * 2)
            
            let hourly = Array(entry.weather.hourlyForecast.prefix(12))
            
            if hourly.isEmpty {
                 Path { path in
                    path.move(to: CGPoint(x: 0, y: proxy.size.height / 2))
                    path.addLine(to: CGPoint(x: width, y: proxy.size.height / 2))
                 }
                 .stroke(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            } else {
                let temps = hourly.compactMap { Double($0.temperature.replacingOccurrences(of: "°", with: "")) }
                
                if let minTemp = temps.min(), let maxTemp = temps.max(), maxTemp > minTemp {
                    let range = maxTemp - minTemp
                    
                    // Gradient Fill
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: viewHeight + padding)) // Bottom Left
                        
                        for (index, temp) in temps.enumerated() {
                            let x = width * CGFloat(index) / CGFloat(max(1, temps.count - 1))
                            let normalized = (temp - minTemp) / range
                            let y = viewHeight - (CGFloat(normalized) * viewHeight) + padding
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                        
                        path.addLine(to: CGPoint(x: width, y: viewHeight + padding)) // Bottom Right
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.white.opacity(0.4), Color.white.opacity(0.0)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    // Line Stroke
                    Path { path in
                        for (index, temp) in temps.enumerated() {
                            let x = width * CGFloat(index) / CGFloat(max(1, temps.count - 1))
                            let normalized = (temp - minTemp) / range
                            let y = viewHeight - (CGFloat(normalized) * viewHeight) + padding
                            
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    
                    // Labels (Start, Middle, End)
                    let indices = [0, temps.count / 2, temps.count - 1]
                    
                    ForEach(indices, id: \.self) { index in
                        if index < temps.count {
                            let temp = temps[index]
                            let x = width * CGFloat(index) / CGFloat(max(1, temps.count - 1))
                            let normalized = (temp - minTemp) / range
                            let y = viewHeight - (CGFloat(normalized) * viewHeight) + padding
                            
                            VStack(spacing: 0) {
                                // Icon
                                Image(systemName: WidgetIconHelper.getIcon(for: hourly[index].condition, isMinimalist: true))
                                    .font(.system(size: 8))
                                    .foregroundColor(.white.opacity(0.9))
                                    .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                                
                                Text("\(Int(temp))°")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
                            }
                            .position(x: x, y: y - 14)
                        }
                    }
                } else {
                     // Flat line fallback
                     Path { path in
                        path.move(to: CGPoint(x: 0, y: proxy.size.height / 2))
                        path.addLine(to: CGPoint(x: width, y: proxy.size.height / 2))
                     }
                     .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Home Screen Expansion Widgets

// 1. Forecast Widget (Daily Focus)
struct BreezyForecastWidget: Widget {
    let kind: String = "BreezyForecastWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ForecastWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Daily Forecast")
        .description("View the forecast for the upcoming days.")
        #if os(iOS)
        .supportedFamilies([.systemMedium, .systemLarge])
        #endif
    }
}

struct ForecastWidgetEntryView: View {
    let entry: WeatherEntry
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        switch family {
        case .systemMedium:
            ForecastMediumView(entry: entry)
        case .systemLarge:
            ForecastLargeView(entry: entry)
        default:
            ForecastMediumView(entry: entry)
        }
    }
}

struct ForecastMediumView: View {
    let entry: WeatherEntry
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 0) {
            // Show today + next 4 days (5 total for full width)
            let days = Array(entry.weather.dailyForecast.prefix(5))
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                VStack(spacing: 6) {
                    Text(index == 0 ? "Today" : day.dayName.prefix(3))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    
                    Image(systemName: WidgetIconHelper.getIcon(for: day.condition, isMinimalist: true))
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .symbolRenderingMode(.hierarchical)
                        .frame(height: 28)
                    
                    VStack(spacing: 0) {
                         Text(day.highTemp.replacingOccurrences(of: "°", with: "") + "°")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(day.lowTemp.replacingOccurrences(of: "°", with: "") + "°")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                .frame(maxWidth: .infinity)
                
                if index < days.count - 1 {
                    Divider()
                        .background(Color.white.opacity(0.15))
                        .frame(height: 40)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .containerBackground(for: .widget) {
            LinearGradient(
                gradient: Gradient(colors: WeatherThemeHelper.gradientColors(for: entry.weather.condition, isDark: colorScheme == .dark)),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct ForecastLargeView: View {
    let entry: WeatherEntry
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                 Text("7-Day Forecast")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer()
                Text(entry.weather.city)
                     .font(.system(size: 13, weight: .medium))
                     .foregroundColor(.white.opacity(0.6))
                     .lineLimit(1)
                     .minimumScaleFactor(0.8)
            }
            .padding(.bottom, 10)
            .padding(.horizontal, 4)
            
            // 7-Day List (Today + 6)
            let days = Array(entry.weather.dailyForecast.prefix(7))
            VStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    HStack {
                        Text(index == 0 ? "Today" : day.dayName)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(width: 60, alignment: .leading)
                        
                        Spacer()
                        
                        Image(systemName: WidgetIconHelper.getIcon(for: day.condition, isMinimalist: true))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.white)
                            .font(.system(size: 16))
                        
                        Spacer()
                        
                        HStack(spacing: 12) {
                            Text(day.lowTemp.replacingOccurrences(of: "°", with: "") + "°")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(width: 35, alignment: .trailing)
                            
                            // Visual Bar (Simple)
                            Capsule()
                                .fill(LinearGradient(colors: [.blue.opacity(0.3), .orange.opacity(0.3)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: 40, height: 4)
                            
                            Text(day.highTemp.replacingOccurrences(of: "°", with: "") + "°")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(width: 35, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 6)
                    
                    if index < days.count - 1 {
                        Divider().background(Color.white.opacity(0.1))
                    }
                }
            }
        }
        .padding(16)
        .containerBackground(for: .widget) {
            LinearGradient(
                gradient: Gradient(colors: WeatherThemeHelper.gradientColors(for: entry.weather.condition, isDark: colorScheme == .dark)),
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

// MARK: - Mock Data for Previews

extension WeatherEntry {
    static var mock: WeatherEntry {
        WeatherEntry(date: Date(), weather: .mock)
    }
}

extension WidgetWeatherData {
    static var mock: WidgetWeatherData {
        WidgetWeatherData(
            city: "San Francisco",
            temperature: "72°",
            condition: "Sunny",
            emoji: "☀️",
            highTemp: "78°",
            lowTemp: "62°",
            hourlyForecast: convertHourly([
                ("Now", "☀️", "72°"),
                ("1 PM", "☀️", "74°"),
                ("2 PM", "⛅️", "75°"),
                ("3 PM", "⛅️", "73°"),
                ("4 PM", "☁️", "70°"),
                ("5 PM", "☁️", "68°"),
                ("6 PM", "🌙", "65°"),
                ("7 PM", "🌙", "62°"),
                ("8 PM", "🌙", "60°"),
                ("9 PM", "🌙", "58°"),
                ("10 PM", "🌙", "57°"),
                ("11 PM", "🌙", "56°")
            ]),
            timestamp: Date(),
            useMinimalistIcons: true,
            uvIndex: 6,
            pressure: "1012 hPa",
            windSpeed: "12 mph",
            rainChance: "0%",
            rainAmount: "0.0 mm",
            latitude: 37.7749,
            longitude: -122.4194,
            conditionCode: "sun.max.fill",
            isDaylight: true,
            minTemp: "62°",
            maxTemp: "78°",
            humidity: "45%",
            visibility: "10 mi",
            sunrise: Date(),
            sunset: Date().addingTimeInterval(3600 * 8),
            moonPhase: "Waxing Gibbous",
            moonIllumination: 0.75,
            windDirectionDegrees: 180.0,
            dailyForecast: [
                WidgetDailyForecast(dayName: "Monday", highTemp: "78°", lowTemp: "62°", condition: "sun.max.fill"),
                WidgetDailyForecast(dayName: "Tuesday", highTemp: "75°", lowTemp: "60°", condition: "cloud.sun.fill"),
                WidgetDailyForecast(dayName: "Wednesday", highTemp: "70°", lowTemp: "58°", condition: "cloud.fill"),
                WidgetDailyForecast(dayName: "Thursday", highTemp: "68°", lowTemp: "57°", condition: "cloud.rain.fill"),
                WidgetDailyForecast(dayName: "Friday", highTemp: "72°", lowTemp: "59°", condition: "sun.max.fill"),
                WidgetDailyForecast(dayName: "Saturday", highTemp: "76°", lowTemp: "61°", condition: "sun.max.fill"),
                WidgetDailyForecast(dayName: "Sunday", highTemp: "79°", lowTemp: "63°", condition: "sun.max.fill")
            ]
        )
    }
    
    static func convertHourly(_ data: [(String, String, String)]) -> [WidgetHourlyForecast] {
        data.map { WidgetHourlyForecast(time: $0.0, temperature: $0.2, emoji: $0.1, condition: "sun.max.fill") }
    }
}

// MARK: - Previews

#if os(iOS)
#Preview("Weather (Custom)", as: .systemSmall) {
    BreezyWeatherWidget()
} timeline: {
    WeatherEntry.mock
}

#Preview("Compact", as: .systemSmall) {
    BreezyCompactWidget()
} timeline: {
    WeatherEntry.mock
}

#Preview("Detailed", as: .systemLarge) {
    BreezyDetailedWidget()
} timeline: {
    WeatherEntry.mock
}

#Preview("Forecast Medium", as: .systemMedium) {
    BreezyForecastWidget()
} timeline: {
    WeatherEntry.mock
}

#Preview("Forecast Large", as: .systemLarge) {
    BreezyForecastWidget()
} timeline: {
    WeatherEntry.mock
}

#Preview("UV Index", as: .accessoryCircular) {
    BreezyCircularUVWidget()
} timeline: {
    WeatherEntry.mock
}

#Preview("Inline", as: .accessoryInline) {
    BreezyInlineWidget()
} timeline: {
    WeatherEntry.mock
}

#if os(iOS)
#Preview("UV Index (Graph)", as: .systemSmall) {
    BreezyUVWidget()
} timeline: {
    WeatherEntry.mock
}

#Preview("Wind Speed", as: .systemSmall) {
    BreezyWindWidget()
} timeline: {
    WeatherEntry.mock
}
#endif

#Preview("Temperature", as: .accessoryCircular) {
    BreezyCircularTempWidget()
} timeline: {
    WeatherEntry.mock
}

#Preview("Rain", as: .accessoryCircular) {
    BreezyCircularRainWidget()
} timeline: {
    WeatherEntry.mock
}
#Preview("Sun Path", as: .systemSmall) {
    BreezySunWidget()
} timeline: {
    WeatherEntry.mock
}

#Preview("Sun Path (Medium)", as: .systemMedium) {
    BreezySunWidget()
} timeline: {
    WeatherEntry.mock
}

#Preview("Moon Phase", as: .systemSmall) {
    BreezyMoonWidget()
} timeline: {
    WeatherEntry.mock
}

#Preview("Sun Lock (Circular)", as: .accessoryCircular) {
    BreezySunLockWidget()
} timeline: {
    WeatherEntry.mock
}

#Preview("Sun Lock (Rect)", as: .accessoryRectangular) {
    BreezySunLockWidget()
} timeline: {
    WeatherEntry.mock
}

#Preview("Moon Lock", as: .accessoryCircular) {
    BreezyMoonLockWidget()
} timeline: {
    WeatherEntry.mock
}

#Preview("UV Rect Lock", as: .accessoryRectangular) {
    BreezyCircularUVWidget()
} timeline: {
    WeatherEntry.mock
}

#Preview("Temp Rect Lock", as: .accessoryRectangular) {
    BreezyCircularTempWidget()
} timeline: {
    WeatherEntry.mock
}

#Preview("Rain Rect Lock", as: .accessoryRectangular) {
    BreezyCircularRainWidget()
} timeline: {
    WeatherEntry.mock
}

#Preview("Wind Rect Lock", as: .accessoryRectangular) {
    BreezyCircularWindWidget()
} timeline: {
    WeatherEntry.mock
}

#endif
//
//  CustomWidgetModels.swift
//  BreezyWidgetExtension
//
//  Created for Custom Widget Builder (Duplicated for availability)
//

import SwiftUI
import Foundation

// Note: Duplicated from main app to avoid target membership issues without project file access

struct CustomWidgetConfiguration: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var backgroundStyle: WidgetBackgroundStyle
    var customColors: [CustomColor] // Strings for Codable
    var fontStyle: WidgetFontStyle
    var metrics: [WidgetMetricPosition: WidgetMetricType]
    var iconStyle: WidgetIconStyle
    var widgetSize: WidgetSize
    var layoutStyle: WidgetLayout
    
    static var `default`: CustomWidgetConfiguration {
        CustomWidgetConfiguration(
            id: UUID(),
            name: "My Widget",
            backgroundStyle: .gradient,
            customColors: [],
            fontStyle: .system,
            metrics: [
                .topLeft: .uvIndex,
                .topRight: .wind,
                .bottomLeft: .humidity,
                .bottomRight: .visibility
            ],
            iconStyle: .minimalist,
            widgetSize: .small,
            layoutStyle: .standard
        )
    }
}

// MARK: - Enums

enum WidgetSize: String, CaseIterable, Codable, Identifiable {
    case small
    case medium
    case large
    
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum WidgetLayout: String, CaseIterable, Codable, Identifiable {
    case standard // Corners + Center
    case split // Left/Right (Medium)
    case list // List of metrics
    case minimal // Just big temp/icon
    
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum WidgetBackgroundStyle: String, CaseIterable, Codable, Identifiable {
    case solid
    case gradient
    case blur
    case weatherMatch
    
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .solid: return "Solid Color"
        case .gradient: return "Gradient"
        case .blur: return "Blur Material"
        case .weatherMatch: return "Match Weather"
        }
    }
}

enum WidgetFontStyle: String, CaseIterable, Codable, Identifiable {
    case system
    case rounded
    case serif
    case monospaced
    
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    
    var design: Font.Design {
        switch self {
        case .system: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }
}

enum WidgetIconStyle: String, CaseIterable, Codable, Identifiable {
    case minimalist
    case emoji
    case realistic
    
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum WidgetMetricPosition: String, CaseIterable, Codable, Identifiable {
    case topLeft
    case topCenter // New
    case topRight
    case middleLeft // New
    case center
    case middleRight // New
    case bottomLeft
    case bottomCenter // New
    case bottomRight
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topCenter: return "Top Center"
        case .topRight: return "Top Right"
        case .middleLeft: return "Middle Left"
        case .center: return "Center"
        case .middleRight: return "Middle Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomCenter: return "Bottom Center"
        case .bottomRight: return "Bottom Right"
        }
    }
}

enum WidgetMetricType: String, CaseIterable, Codable, Identifiable {
    case temperature
    case condition
    case uvIndex
    case wind
    case humidity
    case visibility
    case feelsLike
    case precipChance
    case rainAmount
    case pressure
    case highLow
    case dailyForecast // New
    case aqi           // New
    case temperatureChart // New
    
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .temperature: return "Temperature"
        case .condition: return "Condition Text"
        case .uvIndex: return "UV Index"
        case .wind: return "Wind Speed"
        case .humidity: return "Humidity"
        case .visibility: return "Visibility"
        case .feelsLike: return "Feels Like"
        case .precipChance: return "Rain Chance"
        case .rainAmount: return "Rain Amount"
        case .pressure: return "Pressure"
        case .highLow: return "High / Low"
        case .dailyForecast: return "Daily Forecast"
        case .aqi: return "Air Quality"
        case .temperatureChart: return "Temp Chart"
        }
    }
    
    var icon: String {
        switch self {
        case .temperature: return "thermometer.medium"
        case .condition: return "cloud.sun.fill"
        case .uvIndex: return "sun.max.fill"
        case .wind: return "wind"
        case .humidity: return "humidity.fill"
        case .visibility: return "eye.fill"
        case .feelsLike: return "figure.stand"
        case .precipChance: return "umbrella.fill"
        case .rainAmount: return "drop.fill"
        case .pressure: return "barometer"
        case .highLow: return "arrow.up.arrow.down"
        case .dailyForecast: return "calendar"
        case .aqi: return "aqi.low"
        case .temperatureChart: return "chart.xyaxis.line"
        }
    }
}

// Helper struct for codable colors
struct CustomColor: Codable, Identifiable, Equatable {
    var id = UUID()
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double
    
    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
    
    init(color: Color) {
        if let components = UIColor(color).cgColor.components {
            if components.count >= 3 {
                self.red = Double(components[0])
                self.green = Double(components[1])
                self.blue = Double(components[2])
                self.opacity = components.count >= 4 ? Double(components[3]) : 1.0
            } else if components.count == 2 {
                // Grayscale
                self.red = Double(components[0])
                self.green = Double(components[0])
                self.blue = Double(components[0])
                self.opacity = Double(components[1])
            } else {
                 // Fallback
                self.red = 1
                self.green = 1
                self.blue = 1
                self.opacity = 1
            }
        } else {
            // Fallback
             self.red = 1
             self.green = 1
             self.blue = 1
             self.opacity = 1
        }
    }
    
    init(r: Double, g: Double, b: Double, a: Double = 1.0) {
        self.red = r
        self.green = g
        self.blue = b
        self.opacity = a
    }
}

// Simple loader helper
struct WidgetConfigLoader {
    static func load() -> CustomWidgetConfiguration? {
        guard let defaults = UserDefaults(suiteName: "group.com.breezy.weather"),
              let data = defaults.data(forKey: "Breezy.CustomWidgetConfig") else {
            return nil
        }
        return try? JSONDecoder().decode(CustomWidgetConfiguration.self, from: data)
    }
}
