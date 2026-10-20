//
//  BreezyWatchComplication.swift
//  Breezy Watch Watch App
//
//  WatchOS complications using WidgetKit
//

import WidgetKit
import SwiftUI
import Charts
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
        if let lastLocation = manager.location,
           lastLocation.timestamp.timeIntervalSinceNow > -60 {
            return lastLocation
        }
        
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            throw NSError(domain: "WatchWidgetLocation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not authorized"])
        }
        
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            manager.requestLocation()
            
            DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in
                guard let self = self, self.continuation != nil else { return }
                self.continuation?.resume(throwing: NSError(domain: "WatchWidgetLocation", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timeout"]))
                self.continuation = nil
            }
        }
    }
    
    @objc func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.first, let cont = continuation {
            cont.resume(returning: location)
            continuation = nil
        }
    }
    
    @objc func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let cont = continuation {
            cont.resume(throwing: error)
            continuation = nil
        }
    }
}

// MARK: - Timeline Provider

class WatchComplicationProvider: TimelineProvider {
    typealias Entry = WatchWeatherEntry

    /// Smart Stack scoring hook — subclasses score their own metric per hour.
    /// Scores are 0…1; watchOS ranks the Smart Stack by them.
    func relevance(for weather: WatchWeatherData, at date: Date) -> TimelineEntryRelevance? {
        // Baseline: the general weather card is always faintly interesting.
        TimelineEntryRelevance(score: 0.15, duration: 3600)
    }

    func placeholder(in context: Context) -> WatchWeatherEntry {
        WatchWeatherEntry(
            date: Date(),
            weather: WatchWeatherData.complication(
                city: "San Francisco",
                temperature: "72°",
                condition: "Sunny",
                emoji: "☀️",
                highTemp: "75°",
                lowTemp: "68°",
                uvIndex: 5,
                windSpeed: "12 mph",
                windDirectionDegrees: 180,
                rainChance: "0%",
                humidity: 45,
                pressure: "1013 hPa"
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchWeatherEntry) -> Void) {
        if let cachedData = loadCachedWeatherData() {
            completion(WatchWeatherEntry(date: Date(), weather: cachedData))
        } else {
            completion(placeholder(in: context))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchWeatherEntry>) -> Void) {
        let cachedData = loadCachedWeatherData()
        let defaults = UserDefaults(suiteName: WatchAppStorageKey.appGroup)

        func createEntries(from data: WatchWeatherData) -> [WatchWeatherEntry] {
            var entries: [WatchWeatherEntry] = []
            let now = Date()
            entries.append(WatchWeatherEntry(
                date: now,
                weather: data,
                relevance: relevance(for: data, at: now)
            ))

            // Per-hour entries carry that hour's real values — rain chance, UV,
            // wind, humidity — so complications stay accurate for hours even
            // between refreshes, and each hour scores its own Smart Stack
            // relevance.
            for offset in 1...7 {
                guard let futureDate = Calendar.current.date(byAdding: .hour, value: offset, to: now) else { continue }
                let futureWeather: WatchWeatherData
                if let matching = data.hourlyForecast.first(where: { Calendar.current.isDate($0.date, equalTo: futureDate, toGranularity: .hour) }) {
                    futureWeather = data.forHour(matching)
                } else {
                    futureWeather = data
                }
                entries.append(WatchWeatherEntry(
                    date: futureDate,
                    weather: futureWeather,
                    relevance: relevance(for: futureWeather, at: futureDate)
                ))
            }
            return entries
        }

        Task {
            struct Coord { let lat: Double; let lon: Double; let name: String? }

            struct LocalSavedLocation: Decodable {
                let id: UUID
                let name: String
                let latitude: Double
                let longitude: Double
            }

            var targetLocation: Coord? = nil

            if let idStr = defaults?.string(forKey: "WatchSelectedLocationID"),
               let savedData = defaults?.data(forKey: "WatchSavedLocations"),
               let savedLocs = try? JSONDecoder().decode([LocalSavedLocation].self, from: savedData),
               let match = savedLocs.first(where: { $0.id.uuidString == idStr }) {

                targetLocation = Coord(lat: match.latitude, lon: match.longitude, name: match.name)
            }

            if targetLocation == nil {
                let shouldFollowGPS = defaults?.bool(forKey: "Breezy.shouldFollowGPS") ?? true

                if shouldFollowGPS {
                    do {
                        let loc = try await WatchWidgetLocationManager.shared.requestLocation()
                        targetLocation = Coord(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude, name: nil)
                        defaults?.set(loc.coordinate.latitude, forKey: "WatchLastLatitude")
                        defaults?.set(loc.coordinate.longitude, forKey: "WatchLastLongitude")
                    } catch {
                    }
                }
            }

            if targetLocation == nil {
                let lat = defaults?.object(forKey: "WatchLastLatitude") as? Double
                let lon = defaults?.object(forKey: "WatchLastLongitude") as? Double
                if let lat, let lon, lat != 0, lon != 0 {
                    targetLocation = Coord(lat: lat, lon: lon, name: nil)
                }
            }

            guard let coords = targetLocation else {
                if let data = cachedData {
                    completion(Timeline(entries: createEntries(from: data), policy: .after(Date().addingTimeInterval(30 * 60))))
                } else {
                    completion(Timeline(entries: [placeholder(in: context)], policy: .after(Date().addingTimeInterval(30 * 60))))
                }
                return
            }

            // City: saved name, else reverse geocode, else the cache's.
            let city: String
            if let manualName = coords.name {
                city = manualName
            } else if let placemarks = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: coords.lat, longitude: coords.lon)),
                      let locality = placemarks.first?.locality {
                city = locality
            } else {
                city = cachedData?.city ?? "My Location"
            }

            // Honor the source selection — Open-Meteo fetches no longer fall
            // back to WeatherKit data the user didn't ask for.
            let fetched: WatchWeatherData
            do {
                switch selectedSource() {
                case .openMeteo:
                    fetched = try await WatchOpenMeteoClient.shared.fetchWeather(
                        latitude: coords.lat,
                        longitude: coords.lon,
                        city: city,
                        units: currentUnits()
                    )
                case .weatherKit:
                    fetched = try await fetchFromWeatherKit(lat: coords.lat, lon: coords.lon, city: city)
                }
                completion(Timeline(entries: createEntries(from: fetched), policy: .after(Date().addingTimeInterval(30 * 60))))
            } catch {
                if let data = cachedData {
                    completion(Timeline(entries: createEntries(from: data), policy: .after(Date().addingTimeInterval(30 * 60))))
                } else {
                    completion(Timeline(entries: [placeholder(in: context)], policy: .after(Date().addingTimeInterval(15 * 60))))
                }
            }
        }
    }

    private func selectedSource() -> WatchSelectedWeatherSource {
        let defaults = UserDefaults(suiteName: WatchAppStorageKey.appGroup)
        return defaults?.string(forKey: WatchAppStorageKey.weatherSource).flatMap(WatchSelectedWeatherSource.init(rawValue:))
            ?? defaults?.string(forKey: WatchAppStorageKey.phoneWeatherSource).flatMap(WatchSelectedWeatherSource.init(rawValue:))
            ?? .weatherKit
    }

    private func currentUnits() -> (temperature: WatchTemperatureUnit, wind: WindSpeedUnit, pressure: PressureUnit, visibility: VisibilityUnit) {
        let defaults = UserDefaults(suiteName: WatchAppStorageKey.appGroup)
        let wind = defaults?.string(forKey: WatchAppStorageKey.windSpeedUnit).flatMap(WindSpeedUnit.init(rawValue:)) ?? .metersPerSecond
        let pressure = defaults?.string(forKey: WatchAppStorageKey.pressureUnit).flatMap(PressureUnit.init(rawValue:)) ?? .hectopascals
        let visibility = defaults?.string(forKey: WatchAppStorageKey.visibilityUnit).flatMap(VisibilityUnit.init(rawValue:)) ?? .kilometers
        return (WatchTemperatureUnit.fromUserDefaults(), wind, pressure, visibility)
    }

    private func fetchFromWeatherKit(lat: Double, lon: Double, city: String) async throws -> WatchWeatherData {
        let weather = try await WeatherService.shared.weather(for: CLLocation(latitude: lat, longitude: lon))
        let defaults = UserDefaults(suiteName: WatchAppStorageKey.appGroup)
        // The value may be "Fahrenheit" (phone push) or "fahrenheit" (watch).
        let isFahrenheit = (defaults?.string(forKey: WatchAppStorageKey.temperatureUnit) ?? "celsius").lowercased().hasPrefix("f")

        func temp(_ measurement: Measurement<UnitTemperature>) -> String {
            let value = isFahrenheit ? measurement.converted(to: .fahrenheit).value : measurement.converted(to: .celsius).value
            return String(format: "%.0f°", value)
        }

        let condition = weather.currentWeather.condition.description
        let daily = weather.dailyForecast.first
        let hourly: [WatchHourlyForecast] = weather.hourlyForecast
            .filter { $0.date >= Date() }
            .prefix(12)
            .map { h in
                WatchHourlyForecast(
                    date: h.date,
                    time: complicationHourString(Calendar.current.component(.hour, from: h.date)),
                    temperature: temp(h.temperature),
                    emoji: "☀️",
                    iconName: WatchWeatherIconHelper.minimalistIcon(for: h.condition.description, at: h.date, sunrise: daily?.sun.sunrise, sunset: daily?.sun.sunset),
                    condition: h.condition.description,
                    precipitationChance: String(format: "%.0f%%", h.precipitationChance * 100)
                )
            }

        let windUnit = currentUnits().wind
        let windMps = weather.currentWeather.wind.speed.converted(to: .metersPerSecond).value

        return WatchWeatherData(
            city: city,
            temperature: temp(weather.currentWeather.temperature),
            feelsLike: temp(weather.currentWeather.apparentTemperature),
            condition: condition,
            emoji: "🌡️",
            iconName: WatchWeatherIconHelper.minimalistIcon(for: condition, sunrise: daily?.sun.sunrise, sunset: daily?.sun.sunset),
            highTemp: daily.map { temp($0.highTemperature) },
            lowTemp: daily.map { temp($0.lowTemperature) },
            hourlyForecast: Array(hourly),
            dailyForecast: [],
            windSpeed: String(format: "%.0f %@", windUnit.convert(windMps), windUnit.displayName),
            windDirection: WatchWindDirectionHelper.cardinalDirection(from: weather.currentWeather.wind.direction.converted(to: .degrees).value),
            windDirectionDegrees: weather.currentWeather.wind.direction.converted(to: .degrees).value,
            uvIndex: Int(weather.currentWeather.uvIndex.value),
            rainChance: daily.map { String(format: "%.0f%%", $0.precipitationChance * 100) },
            humidity: Int(weather.currentWeather.humidity * 100),
            pressure: String(format: "%.0f hPa", weather.currentWeather.pressure.converted(to: .hectopascals).value),
            visibility: nil,
            dewPoint: temp(weather.currentWeather.dewPoint),
            cloudCover: String(format: "%.0f%%", weather.currentWeather.cloudCover * 100),
            sunrise: nil,
            sunset: nil,
            metadata: WatchWeatherMetadata(source: .weatherKit, fetchedAt: Date(), isStale: false, latitude: lat, longitude: lon)
        )
    }

    /// Full-forecast blob first (complete data), then the legacy scalar cache.
    private func loadCachedWeatherData() -> WatchWeatherData? {
        guard let defaults = UserDefaults(suiteName: WatchAppStorageKey.appGroup) else {
            return nil
        }

        if let data = defaults.data(forKey: WatchAppStorageKey.lastForecast),
           let decoded = try? JSONDecoder().decode(WatchWeatherData.self, from: data) {
            var weather = decoded
            weather.metadata.isStale = false
            return weather
        }

        if let city = defaults.string(forKey: "WatchLastCity"),
           let temp = defaults.string(forKey: "WatchLastTemperature"),
           let condition = defaults.string(forKey: "WatchLastCondition"),
           let emoji = defaults.string(forKey: "WatchLastEmoji"),
           !city.isEmpty, !temp.isEmpty, !condition.isEmpty, !emoji.isEmpty {
            return WatchWeatherData(
                city: city,
                temperature: temp,
                feelsLike: nil,
                condition: condition,
                emoji: emoji,
                iconName: WatchWeatherIconHelper.minimalistIcon(for: condition),
                highTemp: defaults.string(forKey: "WatchLastHighTemp"),
                lowTemp: defaults.string(forKey: "WatchLastLowTemp"),
                hourlyForecast: [],
                dailyForecast: [],
                windSpeed: nil,
                windDirection: nil,
                windDirectionDegrees: nil,
                uvIndex: nil,
                rainChance: nil,
                humidity: nil,
                pressure: nil,
                visibility: nil,
                dewPoint: nil,
                cloudCover: nil,
                sunrise: nil,
                sunset: nil,
                metadata: WatchWeatherMetadata(source: .cache, fetchedAt: Date(), isStale: false, latitude: nil, longitude: nil)
            )
        }

        return nil
    }
}

// MARK: - Entry Model

struct WatchWeatherEntry: TimelineEntry {
    let date: Date
    let weather: WatchWeatherData
    var relevance: TimelineEntryRelevance? = nil
}

// MARK: - Per-kind Smart Stack scoring

private func complicationRainChanceFraction(_ weather: WatchWeatherData) -> Double {
    guard let rainChance = weather.rainChance else { return 0 }
    return min(max((Double(rainChance.replacingOccurrences(of: "%", with: "")) ?? 0) / 100, 0), 1)
}

private func complicationWindMetersPerSecond(_ weather: WatchWeatherData) -> Double? {
    guard let text = weather.windSpeed else { return nil }
    let lowered = text.lowercased()
    let digits = lowered.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
    guard let value = Double(digits), value > 0 else { return nil }
    if lowered.contains("km/h") { return value / 3.6 }
    if lowered.contains("mph") { return value / 2.23694 }
    if lowered.contains("knot") { return value / 1.94384 }
    return value
}

/// Rain ranks high exactly when it's going to rain that hour.
final class RainComplicationProvider: WatchComplicationProvider {
    override func relevance(for weather: WatchWeatherData, at date: Date) -> TimelineEntryRelevance? {
        let chance = complicationRainChanceFraction(weather)
        guard chance > 0.1 else { return TimelineEntryRelevance(score: 0.05, duration: 3600) }
        return TimelineEntryRelevance(score: Float(0.3 + chance * 0.7), duration: 3600)
    }
}

/// UV ranks with the index itself, daylight hours only.
final class UVComplicationProvider: WatchComplicationProvider {
    override func relevance(for weather: WatchWeatherData, at date: Date) -> TimelineEntryRelevance? {
        guard let uv = weather.uvIndex, uv > 0 else { return TimelineEntryRelevance(score: 0.03, duration: 3600) }
        return TimelineEntryRelevance(score: Float(0.2 + Double(uv) / 12 * 0.7), duration: 3600)
    }
}

/// Wind ranks with speed.
final class WindComplicationProvider: WatchComplicationProvider {
    override func relevance(for weather: WatchWeatherData, at date: Date) -> TimelineEntryRelevance? {
        guard let mps = complicationWindMetersPerSecond(weather) else { return TimelineEntryRelevance(score: 0.05, duration: 3600) }
        return TimelineEntryRelevance(score: Float(0.1 + min(mps / 20, 1) * 0.6), duration: 3600)
    }
}

/// The sun card spikes around sunrise and sunset.
final class SunComplicationProvider: WatchComplicationProvider {
    override func relevance(for weather: WatchWeatherData, at date: Date) -> TimelineEntryRelevance? {
        for event in [weather.sunriseDate, weather.sunsetDate].compactMap({ $0 }) {
            let delta = abs(event.timeIntervalSince(date))
            if delta <= 45 * 60 {
                return TimelineEntryRelevance(score: 0.85, duration: 3600)
            }
            if delta <= 2 * 3600 {
                return TimelineEntryRelevance(score: 0.4, duration: 3600)
            }
        }
        return TimelineEntryRelevance(score: 0.08, duration: 3600)
    }
}

/// Temperature trend matters most at day-part transitions.
final class TempTrendComplicationProvider: WatchComplicationProvider {
    override func relevance(for weather: WatchWeatherData, at date: Date) -> TimelineEntryRelevance? {
        let hour = Calendar.current.component(.hour, from: date)
        if (6...10).contains(hour) || (17...21).contains(hour) {
            return TimelineEntryRelevance(score: 0.45, duration: 3600)
        }
        return TimelineEntryRelevance(score: 0.2, duration: 3600)
    }
}

final class HumidityComplicationProvider: WatchComplicationProvider {
    override func relevance(for weather: WatchWeatherData, at date: Date) -> TimelineEntryRelevance? {
        guard let humidity = weather.humidity else { return TimelineEntryRelevance(score: 0.05, duration: 3600) }
        return TimelineEntryRelevance(score: Float(0.05 + max(0, Double(humidity - 70)) / 100 * 0.5), duration: 3600)
    }
}

final class PressureComplicationProvider: WatchComplicationProvider {
    override func relevance(for weather: WatchWeatherData, at date: Date) -> TimelineEntryRelevance? {
        TimelineEntryRelevance(score: 0.08, duration: 3600)
    }
}

/// General weather: modest baseline that perks up when precipitation nears.
final class GeneralComplicationProvider: WatchComplicationProvider {
    override func relevance(for weather: WatchWeatherData, at date: Date) -> TimelineEntryRelevance? {
        let chance = complicationRainChanceFraction(weather)
        return TimelineEntryRelevance(score: Float(0.15 + chance * 0.5), duration: 3600)
    }
}

// MARK: - Complication conveniences on the shared model

extension WatchWeatherData {
    /// Compact initializer for complication construction sites.
    static func complication(
        city: String,
        temperature: String,
        condition: String,
        emoji: String,
        iconName: String? = nil,
        highTemp: String? = nil,
        lowTemp: String? = nil,
        hourly: [WatchHourlyForecast] = [],
        uvIndex: Int? = nil,
        windSpeed: String? = nil,
        windDirectionDegrees: Double? = nil,
        rainChance: String? = nil,
        humidity: Int? = nil,
        pressure: String? = nil,
        source: WatchWeatherDataSource = .cache
    ) -> WatchWeatherData {
        WatchWeatherData(
            city: city,
            temperature: temperature,
            feelsLike: nil,
            condition: condition,
            emoji: emoji,
            iconName: iconName ?? WatchWeatherIconHelper.minimalistIcon(for: condition),
            highTemp: highTemp,
            lowTemp: lowTemp,
            hourlyForecast: hourly,
            dailyForecast: [],
            windSpeed: windSpeed,
            windDirection: nil,
            windDirectionDegrees: windDirectionDegrees,
            uvIndex: uvIndex,
            rainChance: rainChance,
            humidity: humidity,
            pressure: pressure,
            visibility: nil,
            dewPoint: nil,
            cloudCover: nil,
            sunrise: nil,
            sunset: nil,
            metadata: WatchWeatherMetadata(source: source, fetchedAt: Date(), isStale: false, latitude: nil, longitude: nil)
        )
    }

    /// Copy with a different hour's values — used when building timeline
    /// entries from the hourly series. Each metric falls back to the current
    /// value when that hour didn't provide one.
    func forHour(_ hour: WatchHourlyForecast) -> WatchWeatherData {
        WatchWeatherData(
            city: city,
            temperature: hour.temperature,
            feelsLike: feelsLike,
            condition: hour.condition,
            emoji: hour.emoji,
            iconName: hour.iconName,
            highTemp: highTemp,
            lowTemp: lowTemp,
            hourlyForecast: hourlyForecast,
            dailyForecast: dailyForecast,
            windSpeed: hour.windSpeedText ?? windSpeed,
            windDirection: windDirection,
            windDirectionDegrees: windDirectionDegrees,
            uvIndex: hour.uvValue ?? uvIndex,
            rainChance: hour.precipitationChance ?? rainChance,
            humidity: hour.humidityPercent ?? humidity,
            pressure: pressure,
            visibility: visibility,
            dewPoint: dewPoint,
            cloudCover: cloudCover,
            sunrise: sunrise,
            sunset: sunset,
            metadata: metadata,
            sunriseDate: sunriseDate,
            sunsetDate: sunsetDate
        )
    }

    /// Humidity formatted the way complication views render it.
    var humidityPercent: String? {
        humidity.map { "\($0)%" }
    }
}

/// 12/24-hour hour labels that match the format used across the watch app.
private func complicationHourString(_ hour: Int) -> String {
    let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.current)
    let uses24Hour = template?.contains("a") != true
    guard !uses24Hour else { return "\(hour)" }
    switch hour {
    case 0: return "12AM"
    case 12: return "12PM"
    case 1..<12: return "\(hour)AM"
    default: return "\(hour - 12)PM"
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
        let rawStr = entry.weather.windSpeed ?? "0"
        let speedVal = Double(rawStr.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 0
        
        Gauge(value: speedVal, in: 0...50) {
            if let degrees = entry.weather.windDirectionDegrees {
                Image(systemName: "arrow.up")
                    .rotationEffect(.degrees(degrees + 180)) // Point IN direction of flow
                    .font(.system(size: 12, weight: .bold))
            } else {
                Image(systemName: "wind")
                    .font(.system(size: 14))
            }
        } currentValueLabel: {
            Text("\(Int(speedVal))")
                 .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircular)
        .tint(.cyan)
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

    /// Today's UV peak from the hourly series, when available.
    private var peak: (value: Int, time: String)? {
        let upcoming = entry.weather.hourlyForecast
            .filter { $0.date >= entry.date }
            .compactMap { hour -> (value: Int, time: String)? in
                guard let uv = hour.uvValue else { return nil }
                return (uv, hour.time)
            }
        return upcoming.max(by: { $0.value < $1.value })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Gauge(value: Double(entry.weather.uvIndex ?? 0), in: 0...12) {
                Text("UV Index")
            } currentValueLabel: {
                Text("\(entry.weather.uvIndex ?? 0)")
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

            if let peak, peak.value > (entry.weather.uvIndex ?? 0) {
                Text("Peaks \(peak.value) at \(peak.time)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
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
        let humidityStr = entry.weather.humidityPercent ?? "0%"
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
        let humidityStr = entry.weather.humidityPercent ?? "0%"
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
                Text("Humidity: \(entry.weather.humidityPercent ?? "0%")")
            }
            HStack {
                Image(systemName: "drop.fill")
                Text(entry.weather.humidityPercent ?? "0%")
            }
        }
    }
}

struct AccessoryCornerHumidityView: View {
    let entry: WatchWeatherEntry
    
    var body: some View {
        let humidityStr = entry.weather.humidityPercent ?? "0%"
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
            AccessoryRectangularRainChartView(entry: entry)
        case .accessoryInline:
            AccessoryInlineRainView(entry: entry)
        #if os(watchOS)
        case .accessoryCorner:
            AccessoryCornerRainView(entry: entry)
        #endif
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
        #if os(watchOS)
        case .accessoryCorner:
            AccessoryCornerUVView(entry: entry)
        #endif
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
        #if os(watchOS)
        case .accessoryCorner:
            AccessoryCornerWindView(entry: entry)
        #endif
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
        #if os(watchOS)
        case .accessoryCorner:
            AccessoryCornerHumidityView(entry: entry)
        #endif
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
        #if os(watchOS)
        case .accessoryCorner:
            AccessoryCornerPressureView(entry: entry)
        #endif
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
        #if os(watchOS)
        case .accessoryCorner:
            AccessoryCornerComplicationView(entry: entry)
        #endif
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
        StaticConfiguration(kind: kind, provider: GeneralComplicationProvider()) { entry in
            BreezyGeneralWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Weather (General)")
        .description("Temperature and overview.")
        #if os(watchOS)
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
        #else
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
        #endif
    }
}

struct BreezyRainWidget: Widget {
    let kind: String = "BreezyRainWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RainComplicationProvider()) { entry in
            BreezyRainWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Rain Chance")
        .description("Precipitation probability.")
        #if os(watchOS)
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
        #else
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
        #endif
    }
}

struct BreezyUVWidget: Widget {
    let kind: String = "BreezyUVWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UVComplicationProvider()) { entry in
            BreezyUVWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("UV Index")
        .description("Current UV intensity.")
        #if os(watchOS)
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
        #else
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
        #endif
    }
}

struct BreezyWindWidget: Widget {
    let kind: String = "BreezyWindWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WindComplicationProvider()) { entry in
            BreezyWindWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Wind")
        .description("Wind speed.")
        #if os(watchOS)
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
        #else
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
        #endif
    }
}

struct BreezyHumidityWidget: Widget {
    let kind: String = "BreezyHumidityWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HumidityComplicationProvider()) { entry in
            BreezyHumidityWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Humidity")
        .description("Relative humidity percentage.")
        #if os(watchOS)
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
        #else
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
        #endif
    }
}

struct BreezyPressureWidget: Widget {
    let kind: String = "BreezyPressureWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PressureComplicationProvider()) { entry in
            BreezyPressureWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Pressure")
        .description("Atmospheric pressure.")
        #if os(watchOS)
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
        #else
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
        #endif
    }
}

// MARK: - Chart Complications (watchOS 10+)

/// Rain chance as a bar chart over the next hours (rectangular family).
struct AccessoryRectangularRainChartView: View {
    var entry: WatchComplicationProvider.Entry

    private struct Bar: Identifiable {
        let id = UUID()
        let label: String
        let value: Double
    }

    private var bars: [Bar] {
        entry.weather.hourlyForecast
            .filter { $0.date >= entry.date }
            .prefix(6)
            .map { hour in
                let chance = hour.precipitationChance
                    .flatMap { Double($0.replacingOccurrences(of: "%", with: "")) }
                return Bar(label: hour.time, value: chance ?? 0)
            }
    }

    var body: some View {
        if bars.isEmpty {
            AccessoryRectangularRainView(entry: entry)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "cloud.rain.fill")
                        .font(.caption2)
                    Text("Rain next \(bars.count)h")
                        .font(.caption2)
                    Spacer()
                    Text("\(entry.weather.rainChance ?? "0%")")
                        .font(.caption2.weight(.bold))
                }
                Chart(bars) { bar in
                    BarMark(
                        x: .value("Hour", bar.label),
                        y: .value("Chance", bar.value)
                    )
                    .foregroundStyle(.cyan.gradient)
                }
                .chartYScale(domain: 0...100)
            }
        }
    }
}

/// Temperature trend chart — the watch-native heart of the overhaul.
struct BreezyTempTrendWidgetEntryView: View {
    var entry: WatchComplicationProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryInline:
            AccessoryInlineTempTrendView(entry: entry)
        default:
            AccessoryRectangularTempTrendView(entry: entry)
        }
    }
}

struct BreezyTempTrendWidget: Widget {
    let kind: String = "BreezyTempTrendWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TempTrendComplicationProvider()) { entry in
            BreezyTempTrendWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Temperature Trend")
        .description("Temperature curve for the next hours.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

struct AccessoryRectangularTempTrendView: View {
    var entry: WatchComplicationProvider.Entry

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let temp: Double
    }

    private var series: [Point] {
        entry.weather.hourlyForecast
            .filter { $0.date >= entry.date }
            .prefix(12)
            .compactMap { hour in
                let digits = hour.temperature.replacingOccurrences(of: "°", with: "").replacingOccurrences(of: "F", with: "").replacingOccurrences(of: "C", with: "")
                guard let value = Double(digits) else { return nil }
                return Point(date: hour.date, temp: value)
            }
    }

    var body: some View {
        if series.count < 2 {
            AccessoryRectangularComplicationView(entry: entry)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("\(entry.weather.temperature)")
                        .font(.headline)
                    Text("next \(series.count)h")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Chart(series) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Temp", point.temp)
                    )
                    .foregroundStyle(.orange.gradient)
                    .interpolationMethod(.catmullRom)
                    AreaMark(
                        x: .value("Time", point.date),
                        y: .value("Temp", point.temp)
                    )
                    .foregroundStyle(.orange.opacity(0.2).gradient)
                    .interpolationMethod(.catmullRom)
                }
            }
        }
    }
}

struct AccessoryInlineTempTrendView: View {
    var entry: WatchComplicationProvider.Entry

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "thermometer.medium")
            Text(entry.weather.temperature)
            if let high = entry.weather.highTemp, let low = entry.weather.lowTemp {
                Text("(\(low)–\(high))")
                    .foregroundStyle(.secondary)
            }
        }
        .widgetLabel {
            if entry.weather.hourlyForecast.filter({ $0.date >= entry.date }).count >= 2 {
                Text("Trend available")
            }
        }
    }
}

// MARK: - Sun Complication

struct BreezySunWidgetEntryView: View {
    var entry: WatchComplicationProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            AccessoryCircularSunView(entry: entry)
        case .accessoryInline:
            AccessoryInlineSunView(entry: entry)
        #if os(watchOS)
        case .accessoryCorner:
            AccessoryCornerSunView(entry: entry)
        #endif
        default:
            AccessoryRectangularSunView(entry: entry)
        }
    }
}

/// Fraction of daylight elapsed, 0…1 (nil at night).
private func daylightProgress(now: Date, sunrise: Date?, sunset: Date?) -> Double? {
    guard let sunrise, let sunset, sunset > sunrise else { return nil }
    guard now >= sunrise, now <= sunset else { return nil }
    return now.timeIntervalSince(sunrise) / sunset.timeIntervalSince(sunrise)
}

struct AccessoryCircularSunView: View {
    let entry: WatchWeatherEntry

    var body: some View {
        if let progress = daylightProgress(now: entry.date, sunrise: entry.weather.sunriseDate, sunset: entry.weather.sunsetDate) {
            Gauge(value: progress) {
                Image(systemName: "sun.max.fill")
            } currentValueLabel: {
                Text("\(Int(progress * 100))%")
                    .font(.headline)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(.orange)
            .containerBackground(for: .widget) { Color.clear }
        } else {
            Image(systemName: "moon.stars.fill")
                .font(.headline)
                .containerBackground(for: .widget) { Color.clear }
        }
    }
}

struct AccessoryRectangularSunView: View {
    let entry: WatchWeatherEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if daylightProgress(now: entry.date, sunrise: entry.weather.sunriseDate, sunset: entry.weather.sunsetDate) != nil {
                Label("Daylight", systemImage: "sun.max.fill")
                    .font(.headline)
            } else {
                Label("Night", systemImage: "moon.stars.fill")
                    .font(.headline)
            }
            HStack {
                if let sunrise = entry.weather.sunrise {
                    Label(sunrise, systemImage: "sunrise.fill")
                }
                Spacer()
                if let sunset = entry.weather.sunset {
                    Label(sunset, systemImage: "sunset.fill")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct AccessoryInlineSunView: View {
    let entry: WatchWeatherEntry

    var body: some View {
        let now = entry.date
        if let sunrise = entry.weather.sunriseDate, now < sunrise {
            Label("Sunrise \(entry.weather.sunrise ?? "")", systemImage: "sunrise.fill")
        } else if let sunset = entry.weather.sunsetDate, now < sunset {
            Label("Sunset \(entry.weather.sunset ?? "")", systemImage: "sunset.fill")
        } else {
            Label("Sunrise \(entry.weather.sunrise ?? "--")", systemImage: "sunrise.fill")
        }
    }
}

struct AccessoryCornerSunView: View {
    let entry: WatchWeatherEntry

    var body: some View {
        Image(systemName: daylightProgress(now: entry.date, sunrise: entry.weather.sunriseDate, sunset: entry.weather.sunsetDate) != nil ? "sun.max.fill" : "moon.stars.fill")
            .foregroundStyle(.orange)
            .widgetLabel {
                Text(entry.weather.sunset ?? entry.weather.sunrise ?? "")
            }
    }
}

struct BreezySunWidget: Widget {
    let kind: String = "BreezySunWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SunComplicationProvider()) { entry in
            BreezySunWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Sun")
        .description("Sunrise, sunset, and daylight progress.")
        #if os(watchOS)
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
        #else
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
        #endif
    }
}

// MARK: - Moon Complication

struct BreezyMoonWidgetEntryView: View {
    var entry: WatchComplicationProvider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            AccessoryCircularMoonView(entry: entry)
        case .accessoryInline:
            AccessoryInlineMoonView(entry: entry)
        #if os(watchOS)
        case .accessoryCorner:
            AccessoryCornerMoonView(entry: entry)
        #endif
        default:
            AccessoryRectangularMoonView(entry: entry)
        }
    }
}

private extension WatchWeatherData {
    var tonightMoon: WatchDailyForecast? {
        dailyForecast.first { $0.moonPhaseName != nil } ?? dailyForecast.first
    }
}

struct AccessoryCircularMoonView: View {
    let entry: WatchWeatherEntry

    var body: some View {
        if let moon = entry.weather.tonightMoon, let illumination = moon.moonIllumination {
            Gauge(value: illumination) {
                Image(systemName: "moonphase.waxing.crescent")
            } currentValueLabel: {
                Text("\(Int((illumination * 100).rounded()))")
                    .font(.headline)
                    .minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(.yellow)
            .containerBackground(for: .widget) { Color.clear }
        } else {
            Image(systemName: "moonphase.mixed")
                .font(.headline)
                .containerBackground(for: .widget) { Color.clear }
        }
    }
}

struct AccessoryRectangularMoonView: View {
    let entry: WatchWeatherEntry

    var body: some View {
        if let moon = entry.weather.tonightMoon {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "moonphase.waxing.crescent")
                        .foregroundStyle(.yellow)
                    Text(moon.moonPhaseName ?? "Moon")
                        .font(.headline)
                        .lineLimit(1)
                }
                if let illumination = moon.moonIllumination {
                    Text("\(Int((illumination * 100).rounded()))% illuminated")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let moonrise = moon.moonrise {
                    Label(WatchDateFormatterHelper.formatTime(moonrise), systemImage: "moonrise.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .containerBackground(for: .widget) { Color.clear }
        } else {
            Label("Moon", systemImage: "moonphase.mixed")
                .containerBackground(for: .widget) { Color.clear }
        }
    }
}

struct AccessoryInlineMoonView: View {
    let entry: WatchWeatherEntry

    var body: some View {
        if let moon = entry.weather.tonightMoon, let illumination = moon.moonIllumination {
            Label("\(moon.moonPhaseName ?? "Moon") \(Int((illumination * 100).rounded()))%", systemImage: "moonphase.waxing.crescent")
        } else {
            Label("Moon", systemImage: "moonphase.mixed")
        }
    }
}

struct AccessoryCornerMoonView: View {
    let entry: WatchWeatherEntry

    var body: some View {
        Image(systemName: "moonphase.waxing.crescent")
            .foregroundStyle(.yellow)
            .widgetLabel {
                if let moon = entry.weather.tonightMoon, let illumination = moon.moonIllumination {
                    Text("\(Int((illumination * 100).rounded()))%")
                }
            }
    }
}

/// Moon ranks high on clear nights (stargazing conditions).
final class MoonComplicationProvider: WatchComplicationProvider {
    override func relevance(for weather: WatchWeatherData, at date: Date) -> TimelineEntryRelevance? {
        guard weather.sunriseDate != nil, weather.sunsetDate != nil,
              weather.sunsetDate.map({ $0 < date }) == true || weather.sunriseDate.map({ $0 > date }) == true else {
            return TimelineEntryRelevance(score: 0.08, duration: 3600)
        }
        let lowered = weather.condition.lowercased()
        let clear = lowered.contains("clear") || lowered.contains("sunny") || lowered.contains("mostly clear")
        let illumination = weather.tonightMoon?.moonIllumination ?? 0
        if clear {
            return TimelineEntryRelevance(score: Float(0.5 + illumination * 0.4), duration: 3600)
        }
        return TimelineEntryRelevance(score: 0.2, duration: 3600)
    }
}

struct BreezyMoonWidget: Widget {
    let kind: String = "BreezyMoonWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MoonComplicationProvider()) { entry in
            BreezyMoonWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Moon")
        .description("Moon phase, illumination, and moonrise.")
        #if os(watchOS)
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
        #else
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
        #endif
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
        BreezyTempTrendWidget()
        BreezySunWidget()
        BreezyMoonWidget()
    }
}
