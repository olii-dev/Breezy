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
    let latitude: Double?
    let longitude: Double?
    
    // New fields for accuracy
    let conditionCode: String?
    let isDaylight: Bool?
    let minTemp: String?

    let maxTemp: String?
    let humidity: String?
    let visibility: String?
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
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
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
    static func gradientColors(for condition: String, isDark: Bool, conditionCode: String? = nil, isDaylight: Bool? = nil) -> [Color] {
        // Use precise logic if fields available
        if let code = conditionCode, let day = isDaylight {
            return getGradient(for: code, isNight: !day, fallbackCondition: condition)
        }
        
        // Fallback
        return getGradient(for: condition, isNight: isDark, fallbackCondition: condition)
    }
    
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
    func placeholder(in context: Context) -> WeatherEntry {
        WeatherEntry(
            date: Date(),
            weather: WidgetWeatherData(
                city: "?",
                temperature: "--",
                condition: "?",
                emoji: "🌡️",
                highTemp: nil,
                lowTemp: nil,
                hourlyForecast: [],
                timestamp: Date(),
                useMinimalistIcons: true,
                uvIndex: nil,
                pressure: nil,
                windSpeed: nil,
                rainChance: nil,
                latitude: nil,
                longitude: nil,
                conditionCode: nil,
                isDaylight: true,
                minTemp: nil,
                maxTemp: nil,
                humidity: nil,
                visibility: nil,
                dailyForecast: []
            )
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> ()) {
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
                            latitude: data.latitude,
                            longitude: data.longitude,
                            conditionCode: data.conditionCode, // Use parent's condition code/daylight for now or map?
                            isDaylight: data.isDaylight,       // Best guess: same as parent unless we calculate sunrise/set for every hour
                            minTemp: data.minTemp,
                            maxTemp: data.maxTemp,
                            humidity: data.humidity,
                            visibility: data.visibility,
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
            
             // 4. Fetch Fresh Data
             do {
                 let location = CLLocation(latitude: coords.lat, longitude: coords.lon)
                let weatherService = WeatherService()
                let weather = try await weatherService.weather(for: location)
                
                // Parse fresh data
                // Need to read user units prefs from App Group Defaults
                let defaults = UserDefaults(suiteName: "group.com.breezy.weather")
                
                // Units
                let tempUnitRaw = defaults?.string(forKey: "Breezy.temperatureUnit") ?? "Celsius"
                let windUnitRaw = defaults?.string(forKey: "Breezy.windSpeedUnit") ?? "m/s"
                let pressUnitRaw = defaults?.string(forKey: "Breezy.pressureUnit") ?? "hPa"
                let visUnitRaw = defaults?.string(forKey: "Breezy.visibilityUnit") ?? "Kilometers"
                // let precipUnitRaw = defaults?.string(forKey: "Breezy.precipitationUnit") ?? "Millimeters"
                
                let isFahrenheit = tempUnitRaw == "Fahrenheit"
                
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
                
                let highStr: String? = (highTemp != nil) ? String(format: "%.0f°", isFahrenheit ? highTemp!.converted(to: .fahrenheit).value : highTemp!.converted(to: .celsius).value) : nil
                let lowStr: String? = (lowTemp != nil) ? String(format: "%.0f°", isFahrenheit ? lowTemp!.converted(to: .fahrenheit).value : lowTemp!.converted(to: .celsius).value) : nil

                // Condition
                let condition = weather.currentWeather.condition.description
                let conditionCode = weather.currentWeather.condition.description // We use description as code for now, or could map enum
                let isDaylight = weather.currentWeather.isDaylight
                
                // Wind
                let windUnit = WindSpeedUnit(rawValue: windUnitRaw) ?? .metersPerSecond
                let windVal = weather.currentWeather.wind.speed.converted(to: .metersPerSecond).value
                let windStr = String(format: "%.0f %@", windUnit.convert(windVal), windUnit.displayName)
                
                // Pressure
                let pressUnit = PressureUnit(rawValue: pressUnitRaw) ?? .hectopascals
                let pressVal = weather.currentWeather.pressure.converted(to: .hectopascals).value
                let pressStr = String(format: "%.0f %@", pressUnit.convert(pressVal), pressUnit.displayName)
                
                // UV
                let uv = Int(weather.currentWeather.uvIndex.value)
                
                // Rain Chance (Next 24h peak or today?) - stick to today's max chance
                let rainChanceVal = daily?.precipitationChance ?? 0.0
                let rainChanceStr = String(format: "%.0f%%", rainChanceVal * 100)
                
                // Humidity
                let humidityVal = weather.currentWeather.humidity
                let humidityStr = String(format: "%.0f%%", humidityVal * 100)
                
                // Visibility
                let visUnit = VisibilityUnit(rawValue: visUnitRaw) ?? .kilometers
                let visVal = weather.currentWeather.visibility.converted(to: .meters).value // Base is meters in kit?
                // Actually visibility is a Measurement<UnitLength>
                let visConverted = weather.currentWeather.visibility.converted(to: .meters).value
                let visFinal = visUnit.convert(visConverted)
                let visStr = String(format: "%.1f %@", visFinal, visUnit.symbol)
                
                // Hourly (Next 24h)
                var hourlyForecasts: [WidgetWeatherData.WidgetHourlyForecast] = []
                let currentHour = calendar.component(.hour, from: currentDate)
                
                // Get next 12 hours from service
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
                    
                    // Simple Emoji mapping (could improve)
                    let hCond = hour.condition.description
                    let hEmoji: String
                    if hCond.lowercased().contains("sun") { hEmoji = "☀️" }
                    else if hCond.lowercased().contains("cloud") { hEmoji = "☁️" }
                    else if hCond.lowercased().contains("rain") { hEmoji = "🌧️" }
                    else { hEmoji = "🌡️" }

                    hourlyForecasts.append(WidgetWeatherData.WidgetHourlyForecast(
                        time: timeStr,
                        temperature: hTempStr,
                        emoji: hEmoji,
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
                    latitude: coords.lat,
                    longitude: coords.lon,
                    conditionCode: conditionCode,
                    isDaylight: isDaylight,
                    minTemp: lowStr,
                    maxTemp: highStr,
                    humidity: humidityStr,
                    visibility: visStr,
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

struct BreezyWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
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
        BreezyWeatherWidget()
        BreezyCompactWidget()
        BreezyDetailedWidget()
        BreezyForecastWidget()
        BreezyConditionsWidget()
        BreezyCircularUVWidget()
        BreezyInlineWidget()
        BreezyCircularTempWidget()
        BreezyCircularRainWidget()
        BreezyCircularWindWidget()
    }
}

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
            AccessoryCircularUVView(entry: entry)
        }
        .configurationDisplayName("UV Index")
        .description("Current UV exposure levels.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct AccessoryCircularUVView: View {
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
            AccessoryCircularTempView(entry: entry)
        }
        .configurationDisplayName("Temperature")
        .description("Current temperature with high/low range.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct AccessoryCircularTempView: View {
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
    
    // Helpers to extract numbers for the gauge
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

// 3. Circular Rain Widget
struct BreezyCircularRainWidget: Widget {
    let kind: String = "BreezyCircularRainWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            AccessoryCircularRainView(entry: entry)
        }
        .configurationDisplayName("Rain Chance")
        .description("Chance of precipitation.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct AccessoryCircularRainView: View {
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

// 4. Circular Wind Widget
struct BreezyCircularWindWidget: Widget {
    let kind: String = "BreezyCircularWindWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            AccessoryCircularWindView(entry: entry)
        }
        .configurationDisplayName("Wind")
        .description("Wind speed and direction.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct AccessoryCircularWindView: View {
    let entry: WeatherEntry
    
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "wind")
                .font(.system(size: 14))
            Text(entry.weather.windSpeed ?? "--")
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .containerBackground(for: .widget) { Color.clear } 
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
                    
                    Image(systemName: WidgetIconHelper.getIcon(for: day.condition, isMinimalist: true))
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .symbolRenderingMode(.hierarchical)
                        .frame(height: 28)
                    
                    VStack(spacing: 0) {
                         Text(day.highTemp.replacingOccurrences(of: "°", with: "") + "°")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        Text(day.lowTemp.replacingOccurrences(of: "°", with: "") + "°")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
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
                Spacer()
                Text(entry.weather.city)
                     .font(.system(size: 13, weight: .medium))
                     .foregroundColor(.white.opacity(0.6))
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
                                .frame(width: 35, alignment: .trailing)
                            
                            // Visual Bar (Simple)
                            Capsule()
                                .fill(LinearGradient(colors: [.blue.opacity(0.3), .orange.opacity(0.3)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: 40, height: 4)
                            
                            Text(day.highTemp.replacingOccurrences(of: "°", with: "") + "°")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
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

// 2. Conditions Widget (Metrics Focus)
struct BreezyConditionsWidget: Widget {
    let kind: String = "BreezyConditionsWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ConditionsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Current Conditions")
        .description("Detailed look at wind, UV, rain, and pressure.")
        #if os(iOS)
        .supportedFamilies([.systemSmall, .systemMedium])
        #endif
    }
}

struct ConditionsWidgetEntryView: View {
    let entry: WeatherEntry
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        switch family {
        case .systemSmall:
            ConditionsSmallView(entry: entry)
        case .systemMedium:
            ConditionsMediumView(entry: entry)
        default:
            ConditionsSmallView(entry: entry)
        }
    }
}

struct ConditionsSmallView: View {
    let entry: WeatherEntry
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ConditionItem(icon: "wind", value: entry.weather.windSpeed ?? "--", label: "Wind")
                ConditionItem(icon: "sun.max.fill", value: "\(entry.weather.uvIndex ?? 0)", label: "UV")
                ConditionItem(icon: "drop.fill", value: entry.weather.rainChance ?? "0%", label: "Rain")
                ConditionItem(icon: "gauge.medium", value: entry.weather.pressure?.components(separatedBy: " ").first ?? "--", label: "hPa") 
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
}

struct ConditionsMediumView: View {
    let entry: WeatherEntry
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(entry.weather.city)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text("Current Conditions")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.bottom, 2)
            
            // 2x4 Grid (8 Metrics)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // Row 1
                ConditionItem(icon: "thermometer.high", value: entry.weather.highTemp?.replacingOccurrences(of: "°", with: "") ?? "--", label: "High")
                ConditionItem(icon: "wind", value: entry.weather.windSpeed ?? "--", label: "Wind")
                ConditionItem(icon: "sun.max.fill", value: "\(entry.weather.uvIndex ?? 0)", label: "UV Index")
                ConditionItem(icon: "humidity", value: entry.weather.humidity ?? "--", label: "Humidity")
                
                // Row 2
                ConditionItem(icon: "thermometer.low", value: entry.weather.lowTemp?.replacingOccurrences(of: "°", with: "") ?? "--", label: "Low")
                ConditionItem(icon: "drop.fill", value: entry.weather.rainChance ?? "0%", label: "Rain")
                ConditionItem(icon: "eye.fill", value: entry.weather.visibility?.components(separatedBy: " ").first ?? "--", label: "Visibility")
                ConditionItem(icon: "gauge.medium", value: entry.weather.pressure?.components(separatedBy: " ").first ?? "--", label: "Pressure")
            }
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
}

struct ConditionItem: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.9))
                Spacer()
            }
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.1))
        .cornerRadius(8)
    }
}
