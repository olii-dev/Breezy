//
//  BreezyWatchComplication.swift
//  Breezy Watch Watch App
//
//  WatchOS complications using WidgetKit
//

import WidgetKit
import SwiftUI
import WeatherKit
import CoreLocation

// MARK: - Watch Widget Location Manager
class WatchWidgetLocationManager: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = WatchWidgetLocationManager()
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    
    func requestLocation() async throws -> CLLocation {
        // OPTIMIZATION: Check if we have a recent location cached by the system
        if let lastLocation = manager.location,
           lastLocation.timestamp.timeIntervalSinceNow > -300 { // 5 mins
            print("⌚️ Watch Widget: Using recent system location (Age: \(Int(-lastLocation.timestamp.timeIntervalSinceNow))s)")
            return lastLocation
        }
        
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            throw NSError(domain: "WatchWidgetLocation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not authorized"])
        }
        
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            manager.requestLocation()
            
            // Timeout safety
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self = self, self.continuation != nil else { return }
                self.continuation?.resume(throwing: NSError(domain: "WatchWidgetLocation", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timeout"]))
                self.continuation = nil
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.first, let cont = continuation {
            cont.resume(returning: location)
            continuation = nil
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let cont = continuation {
            cont.resume(throwing: error)
            continuation = nil
        }
    }
}

// MARK: - Timeline Provider

struct WatchComplicationProvider: TimelineProvider {
    typealias Entry = WatchWeatherEntry
    
    func placeholder(in context: Context) -> WatchWeatherEntry {
        WatchWeatherEntry(
            date: Date(),
            weather: WatchWeatherData(
                city: "San Francisco",
                temperature: "72°F",
                condition: "Sunny",
                emoji: "☀️",
                highTemp: "75°F",
                lowTemp: "68°F",
                hourlyForecast: [],
                uvIndex: 5,
                windSpeed: "12 mph",
                rainChance: "0%",
                humidity: "45%",
                pressure: "1013 hPa"
            )
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (WatchWeatherEntry) -> Void) {
        if let cachedData = loadCachedWeatherData() {
            let entry = WatchWeatherEntry(date: Date(), weather: cachedData)
            completion(entry)
        } else {
            completion(placeholder(in: context))
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchWeatherEntry>) -> Void) {
        // 1. Load cached data
        let cachedData = loadCachedWeatherData()
        
        // 2. Prepare for active fetch
        let defaults = UserDefaults(suiteName: "group.com.breezy.weather")
        let lat = defaults?.double(forKey: "WatchLastLatitude") ?? defaults?.double(forKey: "LastLatitude")
        let lon = defaults?.double(forKey: "WatchLastLongitude") ?? defaults?.double(forKey: "LastLongitude")
        
        // Helper inside getTimeline
        func createEntries(from data: WatchWeatherData) -> [WatchWeatherEntry] {
            var ent: [WatchWeatherEntry] = []
            let now = Date()
            
            // "Now" entry
            ent.append(WatchWeatherEntry(date: now, weather: data))
            
            // Future entries from hourly forecast (next 4 hours)
            for i in 1...4 {
                if let futureDate = Calendar.current.date(byAdding: .hour, value: i, to: now) {
                    let hourComp = Calendar.current.component(.hour, from: futureDate)
                    var futureWeather = data
                    
                    if let matching = data.hourlyForecast.first(where: { h in
                        h.time.starts(with: "\(hourComp)") ||
                        h.time.starts(with: "\(hourComp > 12 ? hourComp - 12 : (hourComp == 0 ? 12 : hourComp))")
                    }) {
                         futureWeather = WatchWeatherData(
                            city: data.city,
                            temperature: matching.temperature,
                            condition: matching.condition,
                            emoji: matching.emoji,
                            highTemp: data.highTemp,
                            lowTemp: data.lowTemp,
                            hourlyForecast: data.hourlyForecast,
                            uvIndex: data.uvIndex, // Keep daily/current stats for now
                            windSpeed: data.windSpeed,
                            rainChance: data.rainChance,
                            humidity: data.humidity,
                            pressure: data.pressure
                        )
                    }
                    ent.append(WatchWeatherEntry(date: futureDate, weather: futureWeather))
                }
            }
            return ent
        }
    
        // 3. Attempt Active Fetch
        
        // Define simple coord struct
        struct Coord { let lat: Double; let lon: Double }
        
        let shouldFollowGPS = defaults?.bool(forKey: "Breezy.shouldFollowGPS") ?? false
        
        Task {
            var targetLocation: Coord? = nil
            
            // Try GPS if enabled
            if shouldFollowGPS {
                do {
                    let loc = try await WatchWidgetLocationManager.shared.requestLocation()
                    targetLocation = Coord(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
                    // Update cache
                    defaults?.set(loc.coordinate.latitude, forKey: "WatchLastLatitude")
                    defaults?.set(loc.coordinate.longitude, forKey: "WatchLastLongitude")
                } catch {
                     print("⌚️ Watch GPS failed: \(error). Using cache.")
                }
            }
            
            // Fallback to cache
            if targetLocation == nil {
                if let lat = lat, let lon = lon, lat != 0, lon != 0 {
                    targetLocation = Coord(lat: lat, lon: lon)
                }
            }
            
            guard let coords = targetLocation else {
                // No location available at all -> Cache or Placeholder
                if let data = cachedData {
                    let entries = createEntries(from: data)
                    completion(Timeline(entries: entries, policy: .after(Date().addingTimeInterval(30 * 60))))
                } else {
                    completion(Timeline(entries: [placeholder(in: context)], policy: .after(Date().addingTimeInterval(30 * 60))))
                }
                return
            }
            
            // 4. Fetch Fresh Data using the target coords
            Task {
                do {
                    // Fetch fresh data
                    let location = CLLocation(latitude: coords.lat, longitude: coords.lon)
                    let weather = try await WeatherService.shared.weather(for: location)
                    
                    // Parse Data
                    let tempUnitStr = defaults?.string(forKey: "Breezy.temperatureUnit") ?? "Celsius"
                    let isFahrenheit = tempUnitStr == "Fahrenheit"
                    
                    // Current
                    let currentTempVal = isFahrenheit ? weather.currentWeather.temperature.converted(to: .fahrenheit).value : weather.currentWeather.temperature.converted(to: .celsius).value
                    let tempStr = String(format: "%.0f°", currentTempVal)
                    let cond = weather.currentWeather.condition.description
                    
                    // High/Low
                    let daily = weather.dailyForecast.first
                    let highVal = isFahrenheit ? daily?.highTemperature.converted(to: .fahrenheit).value : daily?.highTemperature.converted(to: .celsius).value
                    let lowVal = isFahrenheit ? daily?.lowTemperature.converted(to: .fahrenheit).value : daily?.lowTemperature.converted(to: .celsius).value
                    
                    let highStr = highVal.map { String(format: "%.0f°", $0) }
                    let lowStr = lowVal.map { String(format: "%.0f°", $0) }
                    
                    // Hourly
                    var hourlyItems: [WatchHourlyForecast] = []
                    let next12 = weather.hourlyForecast.filter { $0.date >= Date() }.prefix(12)
                    for h in next12 {
                        let hVal = isFahrenheit ? h.temperature.converted(to: .fahrenheit).value : h.temperature.converted(to: .celsius).value
                        let hStr = String(format: "%.0f°", hVal)
                        let timeStr = Calendar.current.component(.hour, from: h.date) > 12 ? "\(Calendar.current.component(.hour, from: h.date) - 12)PM" : "\(Calendar.current.component(.hour, from: h.date))AM"
                        
                        hourlyItems.append(WatchHourlyForecast(
                            time: timeStr,
                            temperature: hStr,
                            emoji: "☀️", // Placeholder
                            condition: h.condition.description
                        ))
                    }
                    
                    // Reverse Geocode
                    var finalCity = cachedData?.city ?? "My Location"
                    let geocoder = CLGeocoder()
                    if let placemarks = try? await geocoder.reverseGeocodeLocation(location),
                       let place = placemarks.first {
                        finalCity = place.locality ?? place.name ?? finalCity
                    }
                    
                    let freshData = WatchWeatherData(
                        city: finalCity,
                        temperature: tempStr,
                        condition: cond,
                        emoji: "🌡️",
                        highTemp: highStr,
                        lowTemp: lowStr,
                        hourlyForecast: hourlyItems,
                        uvIndex: weather.currentWeather.uvIndex.value,
                        windSpeed: "\(Int(weather.currentWeather.wind.speed.value)) \(isFahrenheit ? "mph" : "km/h")",
                        rainChance: "\(Int(weather.dailyForecast.first?.precipitationChance ?? 0 * 100))%",
                        humidity: "\(Int(weather.currentWeather.humidity * 100))%",
                        pressure: nil
                    )
                    
                    print("⌚️ Watch Complication: Fetched FRESH data!")
                    let entries = createEntries(from: freshData)
                    let timeline = Timeline(entries: entries, policy: .after(Date().addingTimeInterval(30 * 60)))
                    completion(timeline)
                    
                } catch {
                    print("⌚️ Watch Complication: Fetch failed (\(error)). Using cache.")
                    if let data = cachedData {
                        let entries = createEntries(from: data)
                        let timeline = Timeline(entries: entries, policy: .after(Date().addingTimeInterval(30 * 60)))
                        completion(timeline)
                    } else {
                        completion(Timeline(entries: [placeholder(in: context)], policy: .after(Date().addingTimeInterval(15 * 60))))
                    }
                }
            }
        }
    }

    private func loadCachedWeatherData() -> WatchWeatherData? {
        guard let defaults = UserDefaults(suiteName: "group.com.breezy.weather") else {
            return nil
        }
        
        // First, try to load from iOS app's shared data (most reliable)
        if let sharedData = defaults.data(forKey: "BreezyWidgetData"),
           let decoded = try? JSONDecoder().decode(SharedWeatherData.self, from: sharedData) {
            
            let hourlyForecast = decoded.hourlyForecast.map { hour in
                WatchHourlyForecast(
                    time: hour.time,
                    temperature: hour.temperature,
                    emoji: hour.emoji,
                    condition: hour.condition ?? ""
                )
            }
            
            return WatchWeatherData(
                city: decoded.city,
                temperature: decoded.temperature,
                condition: decoded.condition,
                emoji: decoded.emoji,
                highTemp: decoded.highTemp,
                lowTemp: decoded.lowTemp,
                hourlyForecast: hourlyForecast,
                uvIndex: decoded.uvIndex,
                windSpeed: decoded.windSpeed,
                rainChance: decoded.rainChance,
                humidity: nil, // Shared metrics might be missing humidity
                pressure: decoded.pressure
            )
        }
        
        // Fallback to watch app's individual keys
        if let city = defaults.string(forKey: "WatchLastCity"),
           let temp = defaults.string(forKey: "WatchLastTemperature"),
           let condition = defaults.string(forKey: "WatchLastCondition"),
           let emoji = defaults.string(forKey: "WatchLastEmoji"),
           !city.isEmpty, !temp.isEmpty, !condition.isEmpty, !emoji.isEmpty {
            return WatchWeatherData(
                city: city,
                temperature: temp,
                condition: condition,
                emoji: emoji,
                highTemp: defaults.string(forKey: "WatchLastHighTemp"),
                lowTemp: defaults.string(forKey: "WatchLastLowTemp"),
                hourlyForecast: [],
                uvIndex: nil,
                windSpeed: nil,
                rainChance: nil,
                humidity: nil,
                pressure: nil
            )
        }
        
        return nil
    }
}

// MARK: - Entry Model

struct WatchWeatherEntry: TimelineEntry {
    let date: Date
    let weather: WatchWeatherData
}

// MARK: - Watch Weather Data Model

struct WatchWeatherData {
    let city: String
    let temperature: String
    let condition: String
    let emoji: String
    let highTemp: String?
    let lowTemp: String?
    let hourlyForecast: [WatchHourlyForecast]
    
    // New Metrics
    let uvIndex: Int?
    let windSpeed: String?
    let rainChance: String?
    let humidity: String?
    let pressure: String?
}

struct WatchHourlyForecast: Identifiable {
    let id = UUID()
    let time: String
    let temperature: String
    let emoji: String
    let condition: String
}

// MARK: - Shared Data Model (from iOS app)

private struct SharedWeatherData: Codable {
    let city: String
    let temperature: String
    let condition: String
    let emoji: String
    let highTemp: String?
    let lowTemp: String?
    let hourlyForecast: [SharedHourlyForecast]
    let timestamp: Date
    let useMinimalistIcons: Bool?
    let uvIndex: Int?
    let pressure: String?
    let windSpeed: String?
    let rainChance: String?
    
    struct SharedHourlyForecast: Codable {
        let time: String
        let temperature: String
        let emoji: String
        let condition: String?
    }
}

// MARK: - Widget Views

struct WatchComplicationView: View {
    var entry: WatchComplicationProvider.Entry
    
    var body: some View {
        AccessoryCircularComplicationView(entry: entry)
    }
}

struct AccessoryRectangularComplicationView: View {
    let entry: WatchWeatherEntry
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) { // Reduced spacing
                HStack {
                    Text(entry.weather.city)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                }
                
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(cleanTemperature(entry.weather.temperature))
                        .font(.system(size: 28, weight: .semibold, design: .rounded)) // Reduced from 34
                    
                    Text(entry.weather.condition)
                        .font(.caption2) // Reduced from caption
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 3)
                }
                .padding(.vertical, 1) // Slight padding for breathing room
                
                // Temp Bar
                if let high = entry.weather.highTemp, let low = entry.weather.lowTemp,
                   let highVal = extractTemperature(from: high),
                   let lowVal = extractTemperature(from: low),
                   let currentVal = extractTemperature(from: entry.weather.temperature) {
                    
                    Gauge(value: currentVal, in: lowVal...highVal) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    } minimumValueLabel: {
                        Text(cleanTemperature(low))
                            .font(.system(size: 8)) // Tiny font
                            .foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text(cleanTemperature(high))
                            .font(.system(size: 8)) // Tiny font
                            .foregroundStyle(.secondary)
                    }
                    .gaugeStyle(.accessoryLinear)
                    .tint(Gradient(colors: [.blue, .green, .orange, .red]))
                    .padding(.top, 1)
                } else {
                    Text(entry.weather.condition)
                        .font(.caption2)
                }
            }
            Spacer()
        }
        .containerBackground(for: .widget) { Color.clear }
    }
    
    private func cleanTemperature(_ temp: String) -> String {
        return temp.replacingOccurrences(of: "°", with: "")
                  .replacingOccurrences(of: "C", with: "")
                  .replacingOccurrences(of: "F", with: "")
                  .trimmingCharacters(in: .whitespaces) + "°"
    }
    
    private func extractTemperature(from string: String) -> Double? {
        let cleaned = string.replacingOccurrences(of: "[^0-9.-]", with: "", options: .regularExpression)
        return Double(cleaned)
    }
}

struct AccessoryCircularComplicationView: View {
    let entry: WatchWeatherEntry
    
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
    
    private var temperatureGradient: some ShapeStyle {
        guard let currentTemp = extractTemperature(from: entry.weather.temperature) else {
            // Default: warm-focused gradient
            let colors: [Color] = [
                Color(red: 0.4, green: 0.9, blue: 1.0),      // Cyan
                Color(red: 0.3, green: 0.95, blue: 0.6),     // Green
                Color(red: 0.7, green: 1.0, blue: 0.3),      // Yellow-green
                Color(red: 1.0, green: 0.95, blue: 0.2),     // Yellow
                Color(red: 1.0, green: 0.7, blue: 0.1),      // Orange
                Color(red: 1.0, green: 0.4, blue: 0.1),     // Red-orange
                Color(red: 1.0, green: 0.2, blue: 0.2),      // Red
                Color(red: 0.4, green: 0.9, blue: 1.0)      // Back to cyan
            ]
            return AngularGradient(
                colors: colors,
                center: .center,
                startAngle: .degrees(-90),
                endAngle: .degrees(270)
            )
        }
        
        // Detect if temperature is in Celsius or Fahrenheit
        let isCelsius = entry.weather.temperature.uppercased().contains("C")
        
        // Convert to a normalized scale
        let normalizedTemp: Double
        if isCelsius {
            normalizedTemp = min(max((currentTemp + 10) / 50, 0), 1)
        } else {
            normalizedTemp = min(max(currentTemp / 100, 0), 1)
        }
        
        // Adaptive gradient: focus on the temperature range around current temp
        // Less blue/cold colors when it's warm, more warm colors
        let colors: [Color]
        
        if normalizedTemp < 0.3 {
            // Cold weather: Show more cold-to-mild colors
            colors = [
                Color(red: 0.2, green: 0.5, blue: 1.0),      // Deep blue
                Color(red: 0.3, green: 0.7, blue: 1.0),      // Light blue
                Color(red: 0.4, green: 0.9, blue: 1.0),      // Cyan
                Color(red: 0.3, green: 0.95, blue: 0.6),   // Green
                Color(red: 0.7, green: 1.0, blue: 0.3),     // Yellow-green
                Color(red: 1.0, green: 0.95, blue: 0.2),    // Yellow
                Color(red: 0.2, green: 0.5, blue: 1.0)      // Back to blue
            ]
        } else if normalizedTemp < 0.6 {
            // Mild weather: Balanced gradient, less blue
            colors = [
                Color(red: 0.4, green: 0.9, blue: 1.0),      // Cyan
                Color(red: 0.3, green: 0.95, blue: 0.6),     // Green
                Color(red: 0.7, green: 1.0, blue: 0.3),      // Yellow-green
                Color(red: 1.0, green: 0.95, blue: 0.2),    // Yellow
                Color(red: 1.0, green: 0.7, blue: 0.1),     // Orange
                Color(red: 1.0, green: 0.4, blue: 0.1),     // Red-orange
                Color(red: 0.4, green: 0.9, blue: 1.0)      // Back to cyan
            ]
        } else {
            // Warm/Hot weather: Focus on warm colors, minimal blue
            colors = [
                Color(red: 0.5, green: 0.95, blue: 0.8),     // Light green-cyan
                Color(red: 0.7, green: 1.0, blue: 0.3),     // Yellow-green
                Color(red: 1.0, green: 0.95, blue: 0.2),     // Yellow
                Color(red: 1.0, green: 0.8, blue: 0.15),   // Yellow-orange
                Color(red: 1.0, green: 0.7, blue: 0.1),     // Orange
                Color(red: 1.0, green: 0.5, blue: 0.1),     // Red-orange
                Color(red: 1.0, green: 0.3, blue: 0.2),     // Red
                Color(red: 1.0, green: 0.2, blue: 0.2),     // Deep red
                Color(red: 0.5, green: 0.95, blue: 0.8)     // Back to light green
            ]
        }
        
        return AngularGradient(
            colors: colors,
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(270)
        )
    }
    
    private var temperatureColor: Color {
        guard let currentTemp = extractTemperature(from: entry.weather.temperature) else {
            return Color(red: 0.4, green: 0.7, blue: 1.0)
        }
        
        // Detect if temperature is in Celsius or Fahrenheit
        let isCelsius = entry.weather.temperature.uppercased().contains("C")
        
        // Convert to a normalized scale for color calculation
        let normalizedTemp: Double
        if isCelsius {
            // Celsius: -10 to 40 is a good range
            normalizedTemp = min(max((currentTemp + 10) / 50, 0), 1)
        } else {
            // Fahrenheit: 0 to 100 is a good range
            normalizedTemp = min(max(currentTemp / 100, 0), 1)
        }
        
        // Smooth color interpolation for center text
        // Creates a more refined, aesthetically pleasing color
        if normalizedTemp < 0.125 {
            // Very cold: Deep blue to light blue
            let t = normalizedTemp / 0.125
            return Color(
                red: 0.2 + (0.3 - 0.2) * t,
                green: 0.5 + (0.7 - 0.5) * t,
                blue: 1.0
            )
        } else if normalizedTemp < 0.25 {
            // Cold: Light blue to cyan
            let t = (normalizedTemp - 0.125) / 0.125
            return Color(
                red: 0.3 + (0.4 - 0.3) * t,
                green: 0.7 + (0.9 - 0.7) * t,
                blue: 1.0
            )
        } else if normalizedTemp < 0.375 {
            // Cool: Cyan to green
            let t = (normalizedTemp - 0.25) / 0.125
            return Color(
                red: 0.4 - (0.4 - 0.3) * t,
                green: 0.9 + (0.95 - 0.9) * t,
                blue: 1.0 - (1.0 - 0.6) * t
            )
        } else if normalizedTemp < 0.5 {
            // Mild: Green to yellow-green
            let t = (normalizedTemp - 0.375) / 0.125
            return Color(
                red: 0.3 + (0.7 - 0.3) * t,
                green: 0.95 + (1.0 - 0.95) * t,
                blue: 0.6 - (0.6 - 0.3) * t
            )
        } else if normalizedTemp < 0.625 {
            // Warm: Yellow-green to yellow
            let t = (normalizedTemp - 0.5) / 0.125
            return Color(
                red: 0.7 + (1.0 - 0.7) * t,
                green: 1.0,
                blue: 0.3 - (0.3 - 0.2) * t
            )
        } else if normalizedTemp < 0.75 {
            // Hot: Yellow to orange
            let t = (normalizedTemp - 0.625) / 0.125
            return Color(
                red: 1.0,
                green: 0.95 - (0.95 - 0.7) * t,
                blue: 0.2 - (0.2 - 0.1) * t
            )
        } else if normalizedTemp < 0.875 {
            // Very hot: Orange to red-orange
            let t = (normalizedTemp - 0.75) / 0.125
            return Color(
                red: 1.0,
                green: 0.7 - (0.7 - 0.4) * t,
                blue: 0.1 - (0.1 - 0.1) * t
            )
        } else {
            // Extremely hot: Red-orange to red
            let t = (normalizedTemp - 0.875) / 0.125
            return Color(
                red: 1.0,
                green: 0.4 - (0.4 - 0.2) * t,
                blue: 0.1 - (0.1 - 0.2) * t
            )
        }
    }
    
    private func extractTemperature(from string: String) -> Double? {
        // Remove all non-numeric characters except minus sign and decimal point
        let cleaned = string.replacingOccurrences(of: "[^0-9.-]", with: "", options: .regularExpression)
        return Double(cleaned)
    }
    
    private func cleanTemperature(_ temp: String) -> String {
        // Remove degree symbol and unit to prevent cutoff
        return temp.replacingOccurrences(of: "°", with: "")
                  .replacingOccurrences(of: "C", with: "")
                  .replacingOccurrences(of: "F", with: "")
                  .trimmingCharacters(in: .whitespaces)
    }
    
    var body: some View {
        Gauge(value: gaugeValue) {
            // Empty label
        } currentValueLabel: {
            Text(cleanTemperature(entry.weather.temperature))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .foregroundColor(.white)
        } minimumValueLabel: {
            if let low = entry.weather.lowTemp {
                Text(cleanTemperature(low))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .opacity(0.9)
            }
        } maximumValueLabel: {
            if let high = entry.weather.highTemp {
                Text(cleanTemperature(high))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .opacity(0.9)
            }
        }
        .gaugeStyle(.accessoryCircular)
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct AccessoryInlineComplicationView: View {
    let entry: WatchWeatherEntry
    
    private func cleanTemperature(_ temp: String) -> String {
        // Remove degree symbol and unit to prevent cutoff
        return temp.replacingOccurrences(of: "°", with: "")
                  .replacingOccurrences(of: "C", with: "")
                  .replacingOccurrences(of: "F", with: "")
                  .trimmingCharacters(in: .whitespaces)
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Text(entry.weather.emoji)
                .font(.system(size: 12))
            Text(cleanTemperature(entry.weather.temperature))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .widgetAccentable()
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct AccessoryCornerComplicationView: View {
    let entry: WatchWeatherEntry
    
    var body: some View {
        if let high = entry.weather.highTemp, let low = entry.weather.lowTemp,
           let highVal = extractTemperature(from: high),
           let lowVal = extractTemperature(from: low),
           let currentVal = extractTemperature(from: entry.weather.temperature) {
            
            Gauge(value: currentVal, in: lowVal...highVal) {
                // Show nothing in the gauge label area
            } currentValueLabel: {
                Text(cleanTemperature(entry.weather.temperature))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(.white)
            .widgetLabel {
                Text(cleanTemperature(high))
                    .font(.system(size: 13, weight: .medium))
            }
            .widgetCurvesContent()
            .containerBackground(for: .widget) { Color.clear }
        } else {
            // Fallback - show temp only
            Text(cleanTemperature(entry.weather.temperature))
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .widgetCurvesContent()
                .containerBackground(for: .widget) { Color.clear }
        }
    }
    
    private func cleanTemperature(_ temp: String) -> String {
        return temp.replacingOccurrences(of: "°", with: "")
                  .replacingOccurrences(of: "C", with: "")
                  .replacingOccurrences(of: "F", with: "")
                  .trimmingCharacters(in: .whitespaces)
    }
    
    private func extractTemperature(from string: String) -> Double? {
        let cleaned = string.replacingOccurrences(of: "[^0-9.-]", with: "", options: .regularExpression)
        return Double(cleaned)
    }
    
    private func temperatureGradient(for temp: Double, isCelsius: Bool) -> LinearGradient {
        let t = isCelsius ? temp : (temp - 32) * 5/9
        
        if t < 0 {
            return LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing)
        } else if t < 10 {
            return LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
        } else if t < 20 {
            return LinearGradient(colors: [.cyan, .green], startPoint: .leading, endPoint: .trailing)
        } else if t < 25 {
            return LinearGradient(colors: [.green, .yellow], startPoint: .leading, endPoint: .trailing)
        } else if t < 30 {
            return LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing)
        } else {
            return LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing)
        }
    }
}

// MARK: - Widget Configuration

// MARK: - Specialized Circular Views

struct AccessoryCircularRainView: View {
    let entry: WatchWeatherEntry
    
    var body: some View {
        let chanceStr = entry.weather.rainChance ?? "0%"
        let chanceVal = Double(chanceStr.replacingOccurrences(of: "%", with: "")) ?? 0
        
        Gauge(value: chanceVal, in: 0...100) {
            Image(systemName: "umbrella.fill")
                .font(.system(size: 10))
        } currentValueLabel: {
            Text("\(Int(chanceVal))%")
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircular)
        .tint(.blue)
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct AccessoryCircularUVView: View {
    let entry: WatchWeatherEntry
    
    var body: some View {
        let uv = Double(entry.weather.uvIndex ?? 0)
        
        Gauge(value: uv, in: 0...12) {
            Text("UV")
                .font(.system(size: 8, weight: .bold))
        } currentValueLabel: {
            Text("\(Int(uv))")
                .font(.system(size: 16, weight: .bold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircular)
        .tint(Gradient(colors: [.green, .yellow, .orange, .red, .purple]))
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct AccessoryCircularWindView: View {
    let entry: WatchWeatherEntry
    
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "wind")
                .font(.system(size: 14))
            Text(entry.weather.windSpeed ?? "--")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - Widget Definitions

extension View {
    func widgetBase(for family: WidgetFamily) -> some View {
        self.widgetAccentable()
            .containerBackground(for: .widget) { Color.clear }
    }
}

struct AccessoryCornerRainView: View {
    let entry: WatchWeatherEntry
    
    var body: some View {
        let chanceStr = entry.weather.rainChance ?? "0%"
        let chanceVal = Double(chanceStr.replacingOccurrences(of: "%", with: "")) ?? 0
        
        Gauge(value: chanceVal, in: 0...100) {
            Image(systemName: "umbrella.fill")
                .font(.system(size: 20))
        } currentValueLabel: {
            Text("\(Int(chanceVal))%")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
        .widgetCurvesContent()
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct AccessoryRectangularRainView: View {
    let entry: WatchWeatherEntry
    
    var body: some View {
        let chanceStr = entry.weather.rainChance ?? "0%"
        let chanceVal = Double(chanceStr.replacingOccurrences(of: "%", with: "")) ?? 0
        
        Gauge(value: chanceVal, in: 0...100) {
            Text("Rain")
        } currentValueLabel: {
            Text("\(Int(chanceVal))%")
                .font(.headline)
        } minimumValueLabel: {
            Text("0%")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } maximumValueLabel: {
            Text("100%")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .gaugeStyle(.accessoryLinear)
        .tint(.blue)
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct AccessoryInlineRainView: View {
    let entry: WatchWeatherEntry
    
    var body: some View {
        ViewThatFits {
            HStack {
                Image(systemName: "umbrella.fill")
                Text("Rain: \(entry.weather.rainChance ?? "0%")")
            }
            HStack {
                Image(systemName: "umbrella.fill")
                Text(entry.weather.rainChance ?? "0%")
            }
        }
    }
}

// MARK: - Specialized Views (UV)

struct AccessoryCornerUVView: View {
    let entry: WatchWeatherEntry
    
    var body: some View {
        let uv = Double(entry.weather.uvIndex ?? 0)
        
        Gauge(value: uv, in: 0...12) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 20))
        } currentValueLabel: {
            Text("\(Int(uv))")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(Gradient(colors: [.green, .yellow, .orange, .red, .purple]))
        .widgetCurvesContent()
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct AccessoryRectangularUVView: View {
    let entry: WatchWeatherEntry
    
    var body: some View {
        let uv = Double(entry.weather.uvIndex ?? 0)
        
        Gauge(value: uv, in: 0...12) {
            Text("UV Index")
        } currentValueLabel: {
            Text("\(Int(uv))")
                .font(.headline)
        } minimumValueLabel: {
            Text("Low")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } maximumValueLabel: {
            Text("High")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .gaugeStyle(.accessoryLinear)
        .tint(Gradient(colors: [.green, .yellow, .orange, .red, .purple]))
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct AccessoryInlineUVView: View {
    let entry: WatchWeatherEntry
    var body: some View {
        ViewThatFits {
            HStack {
                Image(systemName: "sun.max.fill")
                Text("UV Index: \(entry.weather.uvIndex ?? 0)")
            }
            HStack {
                Image(systemName: "sun.max.fill")
                Text("\(entry.weather.uvIndex ?? 0)")
            }
        }
    }
}

// MARK: - Specialized Views (Wind)

struct AccessoryCornerWindView: View {
    let entry: WatchWeatherEntry
    
    var body: some View {
        let rawStr = entry.weather.windSpeed ?? "0"
        let val = Double(rawStr.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 0
        
        Gauge(value: val, in: 0...50) {
            Image(systemName: "wind")
                .font(.system(size: 20))
        } currentValueLabel: {
            Text("\(Int(val))")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
        .widgetCurvesContent()
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct AccessoryRectangularWindView: View {
    let entry: WatchWeatherEntry
    
    var body: some View {
        let rawStr = entry.weather.windSpeed ?? "0"
        let val = Double(rawStr.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 0
        
        Gauge(value: val, in: 0...50) {
            Text("Wind Speed")
        } currentValueLabel: {
            Text(rawStr)
                .font(.headline)
        } minimumValueLabel: {
            Text("0")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } maximumValueLabel: {
            Text("50+")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .gaugeStyle(.accessoryLinear)
        .tint(.cyan)
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct AccessoryInlineWindView: View {
    let entry: WatchWeatherEntry
    
    var body: some View {
        HStack {
            Image(systemName: "wind")
            Text("Wind: \(entry.weather.windSpeed ?? "--")")
        }
    }
}

// MARK: - Specialized Views (Humidity)

struct AccessoryCircularHumidityView: View {
    let entry: WatchWeatherEntry
    
    var body: some View {
        let humidityStr = entry.weather.humidity ?? "0%"
        let humidityVal = Double(humidityStr.replacingOccurrences(of: "%", with: "")) ?? 0
        
        Gauge(value: humidityVal, in: 0...100) {
            Image(systemName: "drop.fill")
                .font(.system(size: 10))
        } currentValueLabel: {
            Text("\(Int(humidityVal))%")
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircular)
        .tint(Gradient(colors: [.cyan, .blue]))
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct AccessoryRectangularHumidityView: View {
    let entry: WatchWeatherEntry
    
    var body: some View {
        let humidityStr = entry.weather.humidity ?? "0%"
        let humidityVal = Double(humidityStr.replacingOccurrences(of: "%", with: "")) ?? 0
        
        Gauge(value: humidityVal, in: 0...100) {
            Text("Humidity")
        } currentValueLabel: {
            Text(humidityStr)
                .font(.headline)
        } minimumValueLabel: {
            Text("Dry")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } maximumValueLabel: {
            Text("Humid")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .gaugeStyle(.accessoryLinear)
        .tint(Gradient(colors: [.cyan, .blue]))
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct AccessoryInlineHumidityView: View {
    let entry: WatchWeatherEntry
    
    var body: some View {
        ViewThatFits {
            HStack {
                Image(systemName: "drop.fill")
                Text("Humidity: \(entry.weather.humidity ?? "0%")")
            }
            HStack {
                Image(systemName: "drop.fill")
                Text(entry.weather.humidity ?? "0%")
            }
        }
    }
}

struct AccessoryCornerHumidityView: View {
    let entry: WatchWeatherEntry
    
    var body: some View {
        let humidityStr = entry.weather.humidity ?? "0%"
        let humidityVal = Double(humidityStr.replacingOccurrences(of: "%", with: "")) ?? 0
        
        Gauge(value: humidityVal, in: 0...100) {
            Image(systemName: "drop.fill")
                .font(.system(size: 20))
        } currentValueLabel: {
            Text("\(Int(humidityVal))%")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
        .widgetCurvesContent()
        .containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - Specialized Views (Pressure)

struct AccessoryCircularPressureView: View {
    let entry: WatchWeatherEntry
    
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.system(size: 14))
            if let pressure = entry.weather.pressure {
                Text(pressure)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("--")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct AccessoryRectangularPressureView: View {
    let entry: WatchWeatherEntry
    
    var body: some View {
        HStack {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.title2)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Pressure")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(entry.weather.pressure ?? "--")
                    .font(.headline)
                    .lineLimit(1)
            }
            Spacer()
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct AccessoryInlinePressureView: View {
    let entry: WatchWeatherEntry
    
    var body: some View {
        ViewThatFits {
            HStack {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                Text("Pressure: \(entry.weather.pressure ?? "--")")
            }
            HStack {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                Text(entry.weather.pressure ?? "--")
            }
        }
    }
}

struct AccessoryCornerPressureView: View {
    let entry: WatchWeatherEntry
    
    var body: some View {
        let pressureStr = entry.weather.pressure ?? "1013"
        let pressureVal = Double(pressureStr.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 1013
        
        Gauge(value: pressureVal, in: 950...1050) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                .font(.system(size: 18))
        } currentValueLabel: {
            Text("\(Int(pressureVal))")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(.gray)
        .widgetCurvesContent()
        .containerBackground(for: .widget) { Color.clear }
    }
}


// MARK: - Widget Definitions



// MARK: - Entry Views (Family Switchers)

struct BreezyRainWidgetEntryView: View {
    var entry: WatchComplicationProvider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .accessoryCircular:
            AccessoryCircularRainView(entry: entry)
        case .accessoryRectangular:
            AccessoryRectangularRainView(entry: entry)
        case .accessoryInline:
            AccessoryInlineRainView(entry: entry)
        default:
            AccessoryCircularRainView(entry: entry)
        }
    }
}

struct BreezyUVWidgetEntryView: View {
    var entry: WatchComplicationProvider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .accessoryCircular:
            AccessoryCircularUVView(entry: entry)
        case .accessoryRectangular:
            AccessoryRectangularUVView(entry: entry)
        case .accessoryInline:
            AccessoryInlineUVView(entry: entry)
        default:
            AccessoryCircularUVView(entry: entry)
        }
    }
}

struct BreezyWindWidgetEntryView: View {
    var entry: WatchComplicationProvider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .accessoryCircular:
            AccessoryCircularWindView(entry: entry)
        case .accessoryRectangular:
            AccessoryRectangularWindView(entry: entry)
        case .accessoryInline:
            AccessoryInlineWindView(entry: entry)
        default:
            AccessoryCircularWindView(entry: entry)
        }
    }
}

struct BreezyHumidityWidgetEntryView: View {
    var entry: WatchComplicationProvider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .accessoryCircular:
            AccessoryCircularHumidityView(entry: entry)
        case .accessoryRectangular:
            AccessoryRectangularHumidityView(entry: entry)
        case .accessoryInline:
            AccessoryInlineHumidityView(entry: entry)
        default:
            AccessoryCircularHumidityView(entry: entry)
        }
    }
}

struct BreezyPressureWidgetEntryView: View {
    var entry: WatchComplicationProvider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .accessoryCircular:
            AccessoryCircularPressureView(entry: entry)
        case .accessoryRectangular:
            AccessoryRectangularPressureView(entry: entry)
        case .accessoryInline:
            AccessoryInlinePressureView(entry: entry)
        default:
            AccessoryCircularPressureView(entry: entry)
        }
    }
}

struct BreezyGeneralWidgetEntryView: View {
    var entry: WatchComplicationProvider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .accessoryCircular:
            AccessoryCircularComplicationView(entry: entry)
        case .accessoryCorner:
            AccessoryCornerComplicationView(entry: entry)
        case .accessoryRectangular:
            AccessoryRectangularComplicationView(entry: entry)
        case .accessoryInline:
            AccessoryInlineComplicationView(entry: entry)
        default:
            AccessoryCircularComplicationView(entry: entry)
        }
    }
}

struct BreezyGeneralWeatherWidget: Widget {
    let kind: String = "BreezyGeneralWeatherWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchComplicationProvider()) { entry in
            BreezyGeneralWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Weather (General)")
        .description("Temperature and overview.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct BreezyRainWidget: Widget {
    let kind: String = "BreezyRainWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchComplicationProvider()) { entry in
            BreezyRainWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Rain Chance")
        .description("Precipitation probability.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct BreezyUVWidget: Widget {
    let kind: String = "BreezyUVWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchComplicationProvider()) { entry in
            BreezyUVWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("UV Index")
        .description("Current UV intensity.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct BreezyWindWidget: Widget {
    let kind: String = "BreezyWindWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchComplicationProvider()) { entry in
            BreezyWindWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Wind")
        .description("Wind speed.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct BreezyHumidityWidget: Widget {
    let kind: String = "BreezyHumidityWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchComplicationProvider()) { entry in
            BreezyHumidityWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Humidity")
        .description("Relative humidity percentage.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct BreezyPressureWidget: Widget {
    let kind: String = "BreezyPressureWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchComplicationProvider()) { entry in
            BreezyPressureWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Pressure")
        .description("Atmospheric pressure.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct BreezyWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        BreezyGeneralWeatherWidget()
        BreezyRainWidget()
        BreezyUVWidget()
        BreezyWindWidget()
        BreezyHumidityWidget()
        BreezyPressureWidget()
    }
}
