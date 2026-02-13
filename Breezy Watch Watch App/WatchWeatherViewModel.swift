//
//  WatchWeatherViewModel.swift
//  Breezy Watch Watch App
//
//  View model for Watch app - fetches weather directly from WeatherKit
//

import Foundation
import SwiftUI
import Combine
import CoreLocation
import WeatherKit
import WidgetKit


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


    
    private let weatherService = WeatherService.shared
    private let locationHelper = WatchLocationHelper()
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
        selectLocation(newLocation.id) // Switch to it immediately
    }
    
    func removeLocation(at offsets: IndexSet) {
        let locationsToDelete = offsets.map { savedLocations[$0] }
        if let selected = selectedLocationID, locationsToDelete.contains(where: { $0.id == selected }) {
            selectedLocationID = nil // Fallback to GPS
        }
        
        savedLocations.remove(atOffsets: offsets)
        saveLocations()
        
        Task {
             await loadWeather()
        }
    }
    
    func selectLocation(_ id: UUID?) {
        selectedLocationID = id
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
        isLoading = true
        error = nil
        checkLocationAuthorization()
        
        do {
            // Determine Location & Fetch Strategy
            let location: (latitude: Double, longitude: Double, city: String)
            var weatherData: WatchWeatherData? = nil
            var usedPhone = false
            
            if let selectedID = selectedLocationID,
               let saved = savedLocations.first(where: { $0.id == selectedID }) {
                // MANUAL SELECTION: Use specific coords
                location = (saved.latitude, saved.longitude, saved.name)
                
                // Try to fetch from phone using these coords (saves watch battery/data)
                do {
                    if let phoneData = try await WatchSessionManager.shared.requestWeatherData(for: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)) {
                        print("⌚️ Watch: Received manual location data from iPhone!")
                        weatherData = parsePhoneData(phoneData, city: location.city)
                        usedPhone = true
                    }
                } catch {
                     print("⌚️ Watch: Phone unreachable for manual loc. Falling back to local.")
                }
                
            } else {
                // AUTO / GPS: Try to follow iPhone first
                print("⌚️ Watch: Attempting to follow iPhone location...")
                
                do {
                    // Request with NIL coords -> Asks iPhone for ITS current location
                    if let phoneData = try await WatchSessionManager.shared.requestWeatherData(for: nil) {
                        // Phone responded! Extract City & Coords if possible (we only get city name in reply usually)
                        // The reply has "city", but maybe not exact coords.
                        // We use the city name from phone. Coords might be missing, but we have weather data.
                        
                        let city = phoneData["city"] as? String ?? "Current Location"
                        print("⌚️ Watch: Following iPhone at \(city)!")
                        
                        weatherData = parsePhoneData(phoneData, city: city)
                        usedPhone = true
                        
                        // We might not have exact coords to save to cache, but that's okay for display.
                        // To keep cache valid, we can use 0,0 or try to parse if phone sent them (it doesn't currently).
                        // Let's assume 0,0 for now as we have the data.
                        location = (0, 0, city) 
                    } else {
                         throw NSError(domain: "Watch", code: 1, userInfo: [NSLocalizedDescriptionKey: "Phone returned nil"])
                    }
                } catch {
                    print("⌚️ Watch: Phone unreachable (\(error)). Falling back to Watch GPS.")
                    
                    // Fallback: Watch GPS
                    let gpsData = try await locationHelper.requestLocationAndGetData()
                    location = (gpsData.latitude, gpsData.longitude, gpsData.city)
                    checkLocationAuthorization()
                }
            }
            
            // If we successfully got data from phone, use it
            if let data = weatherData {
                self.weather = data
            } else {
                 // Fallback: Fetch from WeatherKit directly (using the determined location)
                 // If we are here, 'location' is set (either from Manual or GPS fallback)
                 let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
             
                print("⌚️ Watch: Fetching from WeatherKit (Independent Mode)")
                // Fallback: Fetch weather from WeatherKit directly
                let weather = try await weatherService.weather(for: clLocation)
                
                // Parse weather data (Existing Logic)
                let hourly = weather.hourlyForecast
                let daily = weather.dailyForecast
                
                // Get current temperature
                let (tempValue, feelsValue) = getCurrentTemperatures(from: weather.currentWeather)
                let symbol = temperatureUnit.symbol
                let tempRaw = String(format: "%.0f°%@", tempValue, symbol)
                let feelsRaw = String(format: "%.0f°%@", feelsValue, symbol)
                
                // Get condition
                let cond = WatchWeatherConditionConverter.description(from: weather.currentWeather.condition)
                let emoji = WatchWeatherIconHelper.emoji(for: cond)
                let iconName = WatchWeatherIconHelper.minimalistIcon(for: cond)
                
                // Get today's high/low
                let (highTemp, lowTemp) = getTodayHighLow(from: daily)
                
                // Extract additional metrics
                let metrics = extractMetrics(from: weather.currentWeather, daily: daily)
                
                // Parse all available hourly forecast data
                let allHourlyForecasts = parseHourlyForecast(from: hourly)
                
                // Filter main hourly forecast to next 24 hours
                let now = Date()
                let calendar = Calendar.current
                let endTime = calendar.date(byAdding: .hour, value: 24, to: now)!
                let mainHourlyForecast = allHourlyForecasts.filter { $0.date >= now && $0.date < endTime }
                
                // Create WatchWeatherData
                let watchData = WatchWeatherData(
                    city: location.city,
                    temperature: tempRaw,
                    feelsLike: feelsRaw,
                    condition: cond,
                    emoji: emoji,
                    iconName: iconName,
                    highTemp: highTemp,
                    lowTemp: lowTemp,
                    hourlyForecast: mainHourlyForecast,
                    dailyForecast: parseDailyForecast(from: daily, hourlyForecast: allHourlyForecasts),
                    windSpeed: metrics.windSpeed,
                    windDirection: metrics.windDirection,
                    windDirectionDegrees: metrics.windDirectionDegrees,
                    uvIndex: metrics.uvIndex,
                    rainChance: metrics.rainChance,
                    humidity: metrics.humidity,
                    pressure: metrics.pressure,
                    visibility: metrics.visibility,
                    dewPoint: metrics.dewPoint,
                    cloudCover: metrics.cloudCover,
                    sunrise: metrics.sunrise,
                    sunset: metrics.sunset
                )
                
                self.weather = watchData
            }

            
            // Cache data (Shared logic for both paths)
            if let w = self.weather, let defaults = UserDefaults(suiteName: "group.com.breezy.weather") {
                defaults.set(location.latitude, forKey: "WatchLastLatitude")
                defaults.set(location.longitude, forKey: "WatchLastLongitude")
                defaults.set(location.city, forKey: "WatchLastCity")
                defaults.set(w.temperature, forKey: "WatchLastTemperature")
                defaults.set(w.condition, forKey: "WatchLastCondition")
                defaults.set(w.emoji, forKey: "WatchLastEmoji")
                defaults.set(w.highTemp, forKey: "WatchLastHighTemp")
                defaults.set(w.lowTemp, forKey: "WatchLastLowTemp")
                defaults.set(Date(), forKey: "WatchLastCacheTimestamp")
                defaults.synchronize()
            }
            
            // Reload complications
            reloadComplications()
            
            isLoading = false
            
        } catch {
            // Error Handling (Same as before)
            var errorMessage = error.localizedDescription
            if let nsError = error as NSError?,
               nsError.domain.contains("WeatherDaemon") || nsError.domain.contains("WeatherKit") {
                if nsError.code == 2 {
                    errorMessage = "WeatherKit authentication failed. Check Bundle ID."
                } else {
                    errorMessage = "WeatherKit error: \(error.localizedDescription)"
                }
            }
            self.error = errorMessage
            isLoading = false
            checkLocationAuthorization()
        }
    }
    
    func requestLocationPermission() {
        Task {
            do {
                _ = try await locationHelper.requestLocationAndGetData()
                await loadWeather()
            } catch {
                // Error will be handled by loadWeather or shown in error state
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func getCurrentTemperatures(from currentWeather: CurrentWeather) -> (temp: Double, feels: Double) {
        if temperatureUnit == .fahrenheit {
            let temp = currentWeather.temperature.converted(to: .fahrenheit).value
            let feels = currentWeather.apparentTemperature.converted(to: .fahrenheit).value
            return (temp, feels)
        } else {
            let temp = currentWeather.temperature.converted(to: .celsius).value
            let feels = currentWeather.apparentTemperature.converted(to: .celsius).value
            return (temp, feels)
        }
    }
    
    private func getTodayHighLow(from daily: Forecast<DayWeather>) -> (high: String?, low: String?) {
        guard let today = daily.forecast.first else { return (nil, nil) }
        
        if temperatureUnit == .fahrenheit {
            let maxF = today.highTemperature.converted(to: .fahrenheit).value
            let minF = today.lowTemperature.converted(to: .fahrenheit).value
            return (String(format: "%.0f°F", maxF), String(format: "%.0f°F", minF))
        } else {
            let maxC = today.highTemperature.converted(to: .celsius).value
            let minC = today.lowTemperature.converted(to: .celsius).value
            return (String(format: "%.0f°C", maxC), String(format: "%.0f°C", minC))
        }
    }
    
    private func parseHourlyForecast(from hourlyForecast: Forecast<HourWeather>) -> [WatchHourlyForecast] {
        var forecasts: [WatchHourlyForecast] = []
        let calendar = Calendar.current
        
        // We need all available hours to filter for future days
        // But for the "hourlyForecast" property on WatchWeatherData (which is used for the main list),
        // we might want to limit it or just return everything and let the view decide.
        // Let's parse EVERYTHING here, and we can filter the main list separate if needed.
        // Actually, keeping the main list to "24h from now" is good, but `WatchDailyForecast` needs its own hours.
        // So let's change this method to return ALL valid hours, and the caller can filter.
        
        // No, `WatchWeatherData.hourlyForecast` is the main list. Let's make this method take a filter range.
        
        for hour in hourlyForecast.forecast {
            // Include everything for now, we'll filter in `filterHourlyForDay`
            // But wait, the main list needs to show the next 24h.
            
           // Let's just process all of them and filter at the call site for the main list?
           // Or better: Process all of them into a big list, pass that to `parseDailyForecast`,
           // and then take the prefix(24) for the main `watchData.hourlyForecast`.
           
            let tempRaw: Double
            if temperatureUnit == .fahrenheit {
                tempRaw = hour.temperature.converted(to: .fahrenheit).value
            } else {
                tempRaw = hour.temperature.converted(to: .celsius).value
            }
            
            let weatherDesc = WatchWeatherConditionConverter.description(from: hour.condition)
            let hourInt = calendar.component(.hour, from: hour.date)
            let timeDisplay = WatchDateFormatterHelper.formatHour(hourInt)
            let emoji = WatchWeatherIconHelper.emoji(for: weatherDesc)
            let iconName = WatchWeatherIconHelper.minimalistIcon(for: weatherDesc)
            
            forecasts.append(WatchHourlyForecast(
                date: hour.date,
                time: timeDisplay,
                temperature: String(format: "%.0f°%@", tempRaw, temperatureUnit.symbol),
                emoji: emoji,
                iconName: iconName,
                condition: weatherDesc
            ))
        }
        
        return forecasts
    }
    
    private func filterHourlyForDay(_ date: Date, allHourly: [WatchHourlyForecast]) -> [WatchHourlyForecast] {
        let calendar = Calendar.current
        // Filter hours that match the day of the given date
        return allHourly.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }
    
    private func parseDailyForecast(from dailyForecast: Forecast<DayWeather>, hourlyForecast: [WatchHourlyForecast]) -> [WatchDailyForecast] {
        var forecasts: [WatchDailyForecast] = []
        let calendar = Calendar.current
        
        // Take next 7 days
        let days = dailyForecast.forecast.prefix(7)
        
        for day in days {
            let date = day.date
            let isToday = calendar.isDateInToday(date)
            
            // Format Day Name (Mon, Tue)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEE"
            let dayName = isToday ? "Today" : dateFormatter.string(from: date)
            
            // Parse Condition
            let weatherDesc = WatchWeatherConditionConverter.description(from: day.condition)
            let emoji = WatchWeatherIconHelper.emoji(for: weatherDesc)
            let iconName = WatchWeatherIconHelper.minimalistIcon(for: weatherDesc)
            
            // Parse Temps
            let lowValue: Double
            let highValue: Double
            let lowStr: String
            let highStr: String
            let windStr: String
            
            if temperatureUnit == .fahrenheit {
                lowValue = day.lowTemperature.converted(to: .fahrenheit).value
                highValue = day.highTemperature.converted(to: .fahrenheit).value
                lowStr = String(format: "%.0f°", lowValue)
                highStr = String(format: "%.0f°", highValue)
                
                let windMph = day.wind.speed.converted(to: .milesPerHour).value
                windStr = String(format: "%.0f mph", windMph)
            } else {
                lowValue = day.lowTemperature.converted(to: .celsius).value
                highValue = day.highTemperature.converted(to: .celsius).value
                lowStr = String(format: "%.0f°", lowValue)
                highStr = String(format: "%.0f°", highValue)
                
                let windKph = day.wind.speed.converted(to: .kilometersPerHour).value
                windStr = String(format: "%.0f km/h", windKph)
            }
            
            let precip = String(format: "%.0f%%", day.precipitationChance * 100)
            let uv = String(format: "%d", Int(day.uvIndex.value))
            
            forecasts.append(WatchDailyForecast(
                dayName: dayName,
                iconName: iconName,
                emoji: emoji,
                lowTemp: lowStr,
                highTemp: highStr,
                lowValue: lowValue,
                highValue: highValue,
                condition: weatherDesc,
                precipitationChance: precip,
                maxWindSpeed: windStr,
                uvIndex: uv,
                sunrise: WatchDateFormatterHelper.formatTime(day.sun.sunrise ?? Date()),
                sunset: WatchDateFormatterHelper.formatTime(day.sun.sunset ?? Date()),
                hourlyForecast: filterHourlyForDay(day.date, allHourly: hourlyForecast)
            ))

        }
        
        return forecasts
    }
    
    // MARK: - Metrics Extraction
    
    private func extractMetrics(from currentWeather: CurrentWeather, daily: Forecast<DayWeather>) -> WatchWeatherMetrics {
        // UV Index
        let uvIndex = Int(currentWeather.uvIndex.value)
        
        // Wind Speed
        let windSpeedValueMPS = currentWeather.wind.speed.converted(to: .metersPerSecond).value
        let convertedWindSpeed = windSpeedUnit.convert(windSpeedValueMPS)
        let windSpeed = String(format: "%.0f %@", convertedWindSpeed, windSpeedUnit.displayName)
        
        // Wind Direction
        let windDirection = currentWeather.wind.direction
        let windDirectionDegrees = windDirection.converted(to: .degrees).value
        let windCardinal = getWindDirectionCardinal(from: windDirectionDegrees)
        
        // Humidity
        let humidity = Int(currentWeather.humidity * 100)
        
        // Rain Chance (from today's forecast)
        let rainChance: String?
        if let today = daily.forecast.first {
            rainChance = String(format: "%.0f%%", today.precipitationChance * 100)
        } else {
            rainChance = nil
        }
        
        // Sun Data
        var sunrise: String?
        var sunset: String?
        if let today = daily.forecast.first {
            if let rise = today.sun.sunrise {
                sunrise = WatchDateFormatterHelper.formatTime(rise)
            }
            if let set = today.sun.sunset {
                sunset = WatchDateFormatterHelper.formatTime(set)
            }
        }
        
        // Pressure
        let pressureValue = currentWeather.pressure
        let pressure: String
        if temperatureUnit == .fahrenheit {
            let inHg = pressureValue.converted(to: .inchesOfMercury).value
            pressure = String(format: "%.1f inHg", inHg)
        } else {
            let hPa = pressureValue.converted(to: .hectopascals).value
            pressure = String(format: "%.0f hPa", hPa)
        }
        
        // Visibility
        let visibilityValue = currentWeather.visibility
        let visibility: String
        if temperatureUnit == .fahrenheit {
            let miles = visibilityValue.converted(to: .miles).value
            visibility = String(format: "%.1f mi", miles)
        } else {
            let km = visibilityValue.converted(to: .kilometers).value
            visibility = String(format: "%.1f km", km)
        }
        
        // Dew Point
        let dewPointValue = currentWeather.dewPoint
        let dewPoint: String
        if temperatureUnit == .fahrenheit {
            let dewF = dewPointValue.converted(to: .fahrenheit).value
            dewPoint = String(format: "%.0f°", dewF)
        } else {
            let dewC = dewPointValue.converted(to: .celsius).value
            dewPoint = String(format: "%.0f°", dewC)
        }
        
        // Cloud Cover
        let cloudCover = String(format: "%.0f%%", currentWeather.cloudCover * 100)
        
        return WatchWeatherMetrics(
            windSpeed: windSpeed,
            windDirection: windCardinal,
            windDirectionDegrees: windDirectionDegrees,
            uvIndex: uvIndex,
            rainChance: rainChance,
            humidity: humidity,
            pressure: pressure,
            visibility: visibility,
            dewPoint: dewPoint,
            cloudCover: cloudCover,
            sunrise: sunrise,
            sunset: sunset
        )
    }
    
    private func getWindDirectionCardinal(from degrees: Double) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees + 22.5) / 45.0) % 8
        return directions[index]
    }
    
    // MARK: - Phone Data Parsing
    
    private func parsePhoneData(_ data: [String: Any], city: String) -> WatchWeatherData {
        // Defaults
        let sym = temperatureUnit.symbol
        
        // Helper to get formatted temp (assuming input is celsius)
        func fmtTemp(_ cVal: Double?) -> String {
            guard let c = cVal else { return "--" }
            if temperatureUnit == .fahrenheit {
                let f = (c * 9/5) + 32
                return String(format: "%.0f°F", f)
            }
            return String(format: "%.0f°C", c)
        }
        
        // 1. Current
        let tempStr = fmtTemp(data["temp_c"] as? Double)
        let feelsStr = fmtTemp(data["feels_c"] as? Double)
        let condition = (data["condition"] as? String) ?? "Unknown"
        let emoji = WatchWeatherIconHelper.emoji(for: condition)
        let iconName = WatchWeatherIconHelper.minimalistIcon(for: condition)
        
        // 2. High/Low
        let highStr = fmtTemp(data["high_c"] as? Double)
        let lowStr = fmtTemp(data["low_c"] as? Double)
        
        // 3. Metrics
        let uvVal = (data["uv"] as? Double) ?? 0
        let uvIndex = Int(uvVal)
        
        let windMps = (data["wind_mps"] as? Double) ?? 0
        let windStr: String
        // Manually convert for display since we don't have Measurement object
        // 1 mps = 3.6 kmh = 2.237 mph
        if windSpeedUnit == .milesPerHour {
             windStr = String(format: "%.0f mph", windMps * 2.23694)
        } else if windSpeedUnit == .kilometersPerHour {
             windStr = String(format: "%.0f km/h", windMps * 3.6)
        } else {
             windStr = String(format: "%.0f m/s", windMps)
        }
        
        let humidity = Int((data["humidity"] as? Double ?? 0) * 100)
        let rainChanceVal = (data["rainChance"] as? Double ?? 0) * 100
        let rainChance = String(format: "%.0f%%", rainChanceVal)
        
        let pressHpa = data["pressure_hpa"] as? Double
        let pressure: String
        if let p = pressHpa {
             if pressureUnit == .inchesOfMercury {
                 pressure = String(format: "%.2f inHg", p * 0.02953)
             } else {
                 pressure = String(format: "%.0f hPa", p)
             }
        } else { pressure = "--" }
        
        let visKm = data["visibility_km"] as? Double
        let visibility: String
        if let v = visKm {
             if visibilityUnit == .miles {
                 visibility = String(format: "%.1f mi", v * 0.621371)
             } else {
                 visibility = String(format: "%.1f km", v)
             }
        } else { visibility = "--" }
        
        let dewC = data["dew_c"] as? Double
        let dewPoint = fmtTemp(dewC)
        
        let cloudVal = (data["cloud"] as? Double ?? 0) * 100
        let cloudCover = String(format: "%.0f%%", cloudVal)
        
        let sunriseTs = data["sunrise"] as? TimeInterval
        let sunsetTs = data["sunset"] as? TimeInterval
        let sunrise = sunriseTs != nil ? WatchDateFormatterHelper.formatTime(Date(timeIntervalSince1970: sunriseTs!)) : nil
        let sunset = sunsetTs != nil ? WatchDateFormatterHelper.formatTime(Date(timeIntervalSince1970: sunsetTs!)) : nil
        
        // 4. Hourly
        var hourlyDisplay: [WatchHourlyForecast] = []
        if let hourlyRaw = data["hourly"] as? [[String: Any]] {
            for h in hourlyRaw {
                guard let ts = h["time"] as? TimeInterval,
                      let tC = h["temp_c"] as? Double,
                      let cond = h["condition"] as? String else { continue }
                
                let date = Date(timeIntervalSince1970: ts)
                let calendar = Calendar.current
                let hourInt = calendar.component(.hour, from: date)
                
                hourlyDisplay.append(WatchHourlyForecast(
                    date: date,
                    time: WatchDateFormatterHelper.formatHour(hourInt),
                    temperature: fmtTemp(tC),
                    emoji: WatchWeatherIconHelper.emoji(for: cond),
                    iconName: WatchWeatherIconHelper.minimalistIcon(for: cond),
                    condition: cond
                ))
            }
        }
        
        // 5. Daily - Construct a minimal "dummy" daily forecast list or re-use single day
        // Since the phone payload was simplified, we might be missing full 7-day forecast.
        // For V1 of Hybrid, we can just fetch the detailed 7-day forecast from local if needed,
        // OR we just accept we only have 24h hourly and Today's details.
        // Let's create a single "Today" entry for the daily list so it doesn't crash.
        // (Enhancement: Phone should send full 7-day list)
        
        var dailyDisplay: [WatchDailyForecast] = []
        
        if let dailyRaw = data["daily"] as? [[String: Any]] {
            let calendar = Calendar.current
            for d in dailyRaw {
                guard let ts = d["time"] as? TimeInterval,
                      let minC = d["low_c"] as? Double,
                      let maxC = d["high_c"] as? Double,
                      let cond = d["condition"] as? String else { continue }
                
                let date = Date(timeIntervalSince1970: ts)
                let isToday = calendar.isDateInToday(date)
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "EEE"
                let dayName = isToday ? "Today" : dateFormatter.string(from: date)
                
                let emoji = WatchWeatherIconHelper.emoji(for: cond)
                let iconName = WatchWeatherIconHelper.minimalistIcon(for: cond)
                
                // Format Temps
                let lowStr: String
                let highStr: String
                let lowVal: Double
                let highVal: Double
                
                if temperatureUnit == .fahrenheit {
                    let minF = (minC * 9/5) + 32
                    let maxF = (maxC * 9/5) + 32
                    lowStr = String(format: "%.0f°", minF)
                    highStr = String(format: "%.0f°", maxF)
                    lowVal = minF
                    highVal = maxF
                } else {
                    lowStr = String(format: "%.0f°", minC)
                    highStr = String(format: "%.0f°", maxC)
                    lowVal = minC
                    highVal = maxC
                }
                
                let rainVal = (d["rainChance"] as? Double ?? 0) * 100
                let rainStr = String(format: "%.0f%%", rainVal)
                
                let uvStr = String(format: "%d", Int(d["uv"] as? Double ?? 0))
                
                let windMps = (d["wind_mps"] as? Double) ?? 0
                let windStr: String
                if windSpeedUnit == .milesPerHour {
                     windStr = String(format: "%.0f mph", windMps * 2.23694)
                } else if windSpeedUnit == .kilometersPerHour {
                     windStr = String(format: "%.0f km/h", windMps * 3.6)
                } else {
                     windStr = String(format: "%.0f m/s", windMps)
                }
                
                let riseTs = d["sunrise"] as? TimeInterval ?? 0
                let setTs = d["sunset"] as? TimeInterval ?? 0
                let riseStr = riseTs > 0 ? WatchDateFormatterHelper.formatTime(Date(timeIntervalSince1970: riseTs)) : "--"
                let setStr = setTs > 0 ? WatchDateFormatterHelper.formatTime(Date(timeIntervalSince1970: setTs)) : "--"
                
                dailyDisplay.append(WatchDailyForecast(
                    dayName: dayName,
                    iconName: iconName,
                    emoji: emoji,
                    lowTemp: lowStr,
                    highTemp: highStr,
                    lowValue: lowVal,
                    highValue: highVal,
                    condition: cond,
                    precipitationChance: rainStr,
                    maxWindSpeed: windStr,
                    uvIndex: uvStr,
                    sunrise: riseStr,
                    sunset: setStr,
                    hourlyForecast: [] // We don't have hourly for future days in simple payload
                ))
            }
        }
        
        // Fallback if empty (Old Phone App version)
        if dailyDisplay.isEmpty {
            dailyDisplay.append(WatchDailyForecast(
                dayName: "Today",
                iconName: iconName,
                emoji: emoji,
                lowTemp: lowStr,
                highTemp: highStr,
                lowValue: (data["low_c"] as? Double) ?? 0,
                highValue: (data["high_c"] as? Double) ?? 0,
                condition: condition,
                precipitationChance: rainChance,
                maxWindSpeed: windStr,
                uvIndex: "\(uvIndex)",
                sunrise: sunrise,
                sunset: sunset,
                hourlyForecast: hourlyDisplay
            ))
        }
        
        return WatchWeatherData(
            city: city,
            temperature: tempStr,
            feelsLike: feelsStr,
            condition: condition,
            emoji: emoji,
            iconName: iconName,
            highTemp: highStr,
            lowTemp: lowStr,
            hourlyForecast: hourlyDisplay,
            dailyForecast: dailyDisplay,
            windSpeed: windStr,
            windDirection: nil, // Not sent in simple payload
            windDirectionDegrees: nil,
            uvIndex: uvIndex,
            rainChance: rainChance,
            humidity: humidity,
            pressure: pressure,
            visibility: visibility,
            dewPoint: dewPoint,
            cloudCover: cloudCover,
            sunrise: sunrise,
            sunset: sunset
        )
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

// MARK: - Watch Data Models

struct WatchWeatherData {
    let city: String
    let temperature: String
    let feelsLike: String?
    let condition: String
    let emoji: String
    let iconName: String
    let highTemp: String?
    let lowTemp: String?
    let hourlyForecast: [WatchHourlyForecast]
    let dailyForecast: [WatchDailyForecast]
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

struct WatchHourlyForecast: Identifiable {
    let id = UUID()
    let date: Date
    let time: String
    let temperature: String
    let emoji: String
    let iconName: String
    let condition: String
}

    struct WatchDailyForecast: Identifiable {
    let id = UUID()
    let dayName: String
    let iconName: String
    let emoji: String
    let lowTemp: String
    let highTemp: String
    let lowValue: Double // For gauge/bar chart
    let highValue: Double // For gauge/bar chart
    let condition: String
    let precipitationChance: String
    let maxWindSpeed: String
    let uvIndex: String
    let sunrise: String?
    let sunset: String?
    let hourlyForecast: [WatchHourlyForecast]
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
