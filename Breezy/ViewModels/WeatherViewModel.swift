//
//  WeatherViewModel.swift
//  Breezy
//
//  Main weather view model
//

import SwiftUI
import Combine
import CoreLocation
import WeatherKit

@MainActor
class WeatherViewModel: ObservableObject {
    
    enum ThemeMode: String, CaseIterable, Identifiable {
        case auto = "Weather"
        case preset = "Pro Theme"
        case custom = "Custom"
        
        var id: String { rawValue }
    }
    
    // Start Watch Session on init
    // Start Watch Session on init
    init() {
        WatchSessionManager.shared.startSession()
        
        // Ensure we sync as soon as the session is properly activated
        WatchSessionManager.shared.onSessionActivation = { [weak self] in
            print("📱 PHONE-VM: Session Active callback received. Syncing context.")
            self?.syncWatchContext()
        }
        
        // Send initial state delayed to ensure properties are loaded (backup)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self.syncWatchContext()
        }
    }
    @Published var currentLocation: LocationData?
    @Published var weather: WeatherInfo?
    @Published var historicalWeather: WeatherInfo? // Time Machine Data - Date 1
    @Published var historicalWeather2: WeatherInfo? // Time Machine Data - Date 2 (for comparison)
    @Published var historicalRange: [HistoricalDataPoint] = [] // For Charts (deprecated)
    @Published var isLoading = false
    @Published var historicalLoading = false
    @Published var error: String?
    @Published var historicalError: String?

    @AppStorage("Breezy.temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.celsius.rawValue
    @AppStorage("Breezy.windSpeedUnit") private var windSpeedUnitRaw: String = WindSpeedUnit.metersPerSecond.rawValue
    @AppStorage("Breezy.pressureUnit") private var pressureUnitRaw: String = PressureUnit.hectopascals.rawValue
    @AppStorage("Breezy.visibilityUnit") private var visibilityUnitRaw: String = VisibilityUnit.kilometers.rawValue
    @AppStorage("Breezy.precipitationUnit") private var precipitationUnitRaw: String = PrecipitationUnit.millimeters.rawValue
    @AppStorage("Breezy.dateFormat") private var dateFormatRaw: String = DateFormat.short.rawValue
    @AppStorage("Breezy.cacheDurationMinutes") var cacheDurationMinutes: Int = 30


    
    @Published var shouldFollowGPS: Bool = CloudStorage.shared.bool(forKey: "Breezy.shouldFollowGPS") {
        didSet {
            CloudStorage.shared.set(shouldFollowGPS, forKey: "Breezy.shouldFollowGPS")
            // Sync to App Group for Widgets
            if let defaults = UserDefaults(suiteName: "group.com.breezy.weather") {
                defaults.set(shouldFollowGPS, forKey: "Breezy.shouldFollowGPS")
            }
            objectWillChange.send()
        }
    }

    // Manage minimalist icons manually to trigger side effects (Watch Sync)
    @Published var useMinimalistIcons: Bool = UserDefaults.standard.object(forKey: "Breezy.useMinimalistIcons") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(useMinimalistIcons, forKey: "Breezy.useMinimalistIcons")
            CloudStorage.shared.set(useMinimalistIcons, forKey: "Breezy.useMinimalistIcons")
            syncWatchContext()
            // Trigger UI update if needed
            objectWillChange.send()
        }
    }

    // Theme Settings
    @Published var themeMode: ThemeMode = ThemeMode(rawValue: UserDefaults.standard.string(forKey: "Breezy.themeMode") ?? "") ?? .auto {
        didSet {
            UserDefaults.standard.set(themeMode.rawValue, forKey: "Breezy.themeMode")
            syncWatchContext()
            objectWillChange.send()
        }
    }
    
    @Published var selectedPresetThemeName: String = UserDefaults.standard.string(forKey: "Breezy.presetTheme") ?? "Cotton Candy" {
        didSet {
            UserDefaults.standard.set(selectedPresetThemeName, forKey: "Breezy.presetTheme")
            syncWatchContext()
            objectWillChange.send()
        }
    }
    
    // Custom theme persistence using the new Codable color helper
    @Published var customTheme: WeatherTheme = {
        if let data = UserDefaults.standard.data(forKey: "Breezy.customTheme"),
           let theme = try? JSONDecoder().decode(WeatherTheme.self, from: data) {
            return theme
        }
        return WeatherTheme.defaultCustom
    }() {
        didSet {
            if let data = try? JSONEncoder().encode(customTheme) {
                UserDefaults.standard.set(data, forKey: "Breezy.customTheme")
            }
            syncWatchContext()
            objectWillChange.send()
        }
    }
    
    // Computed property to resolve the current active theme
    var currentTheme: WeatherTheme {
        let theme: WeatherTheme
        switch themeMode {
        case .custom:
            theme = customTheme
        case .preset:
            if let preset = WeatherTheme.presets.first(where: { $0.name == selectedPresetThemeName }) {
                let isDark = appearanceMode == .dark || (appearanceMode == .auto && UITraitCollection.current.userInterfaceStyle == .dark)
                theme = isDark ? preset.dark : preset.light
            } else {
                theme = WeatherTheme.defaultCustom
            }
        case .auto:
            let condition = weather?.condition ?? "Clear"
            let isDark = appearanceMode == .dark || (appearanceMode == .auto && UITraitCollection.current.userInterfaceStyle == .dark)
            theme = WeatherTheme.theme(for: condition, isDark: isDark)
        }
        
        // SIDE EFFECT: Sync to CloudStorage for Watch
        if let top = theme.topColor.toHex() { CloudStorage.shared.set(top, forKey: "Breezy.theme.top") }
        if let bottom = theme.bottomColor.toHex() { CloudStorage.shared.set(bottom, forKey: "Breezy.theme.bottom") }
        if let text = theme.textColor.toHex() { CloudStorage.shared.set(text, forKey: "Breezy.theme.text") }
        
        return theme
    }
    
    private let weatherService = WeatherService.shared
    private let notificationManager = NotificationManager.shared
    private var previousWeather: WeatherInfo?
    
    var temperatureUnit: TemperatureUnit {
        get { TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius }
        set { 
            temperatureUnitRaw = newValue.rawValue
            syncWatchContext()
        }
    }
    
    var windSpeedUnit: WindSpeedUnit {
        get { WindSpeedUnit(rawValue: windSpeedUnitRaw) ?? .metersPerSecond }
        set { 
            windSpeedUnitRaw = newValue.rawValue
            syncWatchContext()
        }
    }
    
    var pressureUnit: PressureUnit {
        get { PressureUnit(rawValue: pressureUnitRaw) ?? .hectopascals }
        set { 
            pressureUnitRaw = newValue.rawValue
            syncWatchContext()
        }
    }
    
    var visibilityUnit: VisibilityUnit {
        get { VisibilityUnit(rawValue: visibilityUnitRaw) ?? .kilometers }
        set { 
            visibilityUnitRaw = newValue.rawValue
            syncWatchContext()
        }
    }
    
    var precipitationUnit: PrecipitationUnit {
        get { PrecipitationUnit(rawValue: precipitationUnitRaw) ?? .millimeters }
        set { 
            precipitationUnitRaw = newValue.rawValue
            syncWatchContext() // Although we don't sync this yet, good for future
        }
    }
    
    var dateFormat: DateFormat {
        get { DateFormat(rawValue: dateFormatRaw) ?? .short }
        set {
            dateFormatRaw = newValue.rawValue
            syncWatchContext() // Although we don't sync this yet, good for future
        }
    }

    // Quick heuristic to estimate when precipitation will start based on hourly data.
    // Uses the parsed `allHourlyData` (per-hour entries) to find the nearest hour with
    // a meaningful precipitation chance and returns a human-friendly label.
    var rainSoonLabel: String? {
        guard let hours = weather?.allHourlyData, !hours.isEmpty else { return nil }

        let threshold: Double = 0.2 // 20% chance threshold to consider
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)

        for hour in hours {
            let chance = hour.precipitationChance ?? 0.0
            if chance >= threshold {
                // Estimate hours until this hourValue. hour.hourValue is 0-23 local hour.
                var delta = hour.hourValue - currentHour
                if delta < 0 { delta += 24 }

                if delta == 0 {
                    return "Rain likely now"
                } else if delta == 1 {
                    return "Rain within ~1 hour"
                } else if delta <= 6 {
                    return "Rain in ~\(delta) hours"
                } else {
                    // Detected precipitation later today but not soon enough to surface
                    return nil
                }
            }
        }

        return nil
    }
    
    @Published var appearanceMode: AppearanceMode = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "Breezy.appearanceMode") ?? "") ?? .auto {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "Breezy.appearanceMode")
            objectWillChange.send()
        }
    }
    
    @Published var typography: WeatherFont = WeatherFont(rawValue: UserDefaults.standard.string(forKey: "Breezy.typography") ?? "") ?? .system {
        didSet {
            UserDefaults.standard.set(typography.rawValue, forKey: "Breezy.typography")
            syncWatchContext()
            objectWillChange.send()
        }
    }
    
    @Published var visibleMetrics: Set<WeatherMetric> = {
        if let data = CloudStorage.shared.data(forKey: "Breezy.visibleMetrics"),
           let decoded = try? JSONDecoder().decode(Set<WeatherMetric>.self, from: data) {
            return decoded
        }
        // Defaults
        return [.humidity, .pressure, .visibility, .dewPoint, .wind, .rain, .uvIndex]
    }() {
        didSet {
            if let encoded = try? JSONEncoder().encode(visibleMetrics) {
                CloudStorage.shared.set(encoded, forKey: "Breezy.visibleMetrics")
                syncWatchContext()
                objectWillChange.send()
            }
        }
    }
    
    // Radar Map Settings
    enum RadarMapStyle: String, CaseIterable, Identifiable {
        case standard = "Standard"
        case hybrid = "Hybrid"
        case satellite = "Satellite"
        case muted = "Muted"
        
        var id: String { rawValue }
    }
    
    @Published var mapStyle: RadarMapStyle = RadarMapStyle(rawValue: UserDefaults.standard.string(forKey: "Breezy.mapStyle") ?? "") ?? .standard {
        didSet {
            UserDefaults.standard.set(mapStyle.rawValue, forKey: "Breezy.mapStyle")
            objectWillChange.send()
        }
    }
    
    func formattedTemperature(_ tempRaw: Double) -> String {
        let symbol = temperatureUnit.symbol
        return String(format: "%.0f°%@", tempRaw, symbol)
    }

    /// Return a temperature string with a configurable number of decimals.
    func formattedTemperature(_ tempRaw: Double, decimals: Int) -> String {
        let symbol = temperatureUnit.symbol
        let format = "%.\(decimals)f°%@"
        return String(format: format, tempRaw, symbol)
    }
    
    func weatherIcon(for condition: String) -> String {
        if useMinimalistIcons {
            return WeatherIconHelper.minimalistIcon(for: condition)
        } else {
            return WeatherIconHelper.emoji(for: condition)
        }
    }
    
    func currentTheme(colorScheme: ColorScheme) -> WeatherTheme {
        // Determine brightness first (needed for both Auto overrides and Presets)
        let isDark: Bool
        switch appearanceMode {
        case .light:
            isDark = false
        case .dark:
            isDark = true
        case .auto:
            isDark = colorScheme == .dark
        }
        
        switch themeMode {
        case .preset:
            if let preset = WeatherTheme.presets.first(where: { $0.name == selectedPresetThemeName }) {
                return isDark ? preset.dark : preset.light
            }
            // Fallback
            let defaultTheme = WeatherTheme.presets.first?.dark ?? WeatherTheme(topColor: .blue, bottomColor: .cyan, textColor: .white)
            let defaultLightTheme = WeatherTheme.presets.first?.light ?? WeatherTheme(topColor: .blue, bottomColor: .cyan, textColor: .black)
            return isDark ? defaultTheme : defaultLightTheme
            
        case .custom:
            return customTheme
            
        case .auto:
            // Fallthrough to existing logic
            break
        }
        
        // Existing auto logic
        if let weather = weather {
            return WeatherTheme.theme(for: weather.condition, isDark: isDark)
        } else {
            return isDark ?
                WeatherTheme(topColor: Color.blue.opacity(0.5), bottomColor: Color.indigo.opacity(0.7), textColor: .white) :
                WeatherTheme(topColor: Color.blue.opacity(0.8), bottomColor: Color.cyan.opacity(0.7), textColor: Color(red: 0.2, green: 0.2, blue: 0.25))
        }
    }

    func loadCacheIfValid() {
        if let cached = WeatherCache.load() {
            let age = Date().timeIntervalSince1970 - cached.timestamp
            if age <= Double(cacheDurationMinutes * 60) {
                self.weather = cached
                self.currentLocation = cached.location
                
                // Always save cached data to widget/Watch app
                let rainChance = cached.dailyForecast.first?.chanceOfRain
                saveWidgetData(
                    cityName: cached.location.city,
                    tempRaw: cached.temperature,
                    cond: cached.condition,
                    emoji: cached.emoji,
                    highTemp: cached.highTemp,
                    lowTemp: cached.lowTemp,
                    todayHourlyForecast: cached.hourlyForecast,
                    metrics: cached.metrics ?? WeatherMetrics(uvIndex: nil, uvIndexCategory: nil, airQuality: nil, pressure: nil, visibility: nil, dewPoint: nil, humidity: nil, windDirection: nil, windDirectionCardinal: nil, windSpeed: nil, rainChance: nil, cloudCover: nil, sunrise: nil, sunset: nil),
                    rainChance: rainChance
                )
            } else {
                WeatherCache.clear()
            }
        }
    }

    func performStartupIfNeeded(locationHelper: LocationHelper) {
        // Request notification permissions and register categories
        Task {
            _ = await notificationManager.requestAuthorization()
            notificationManager.registerNotificationCategories()
        }
        
        // Check if user has a saved custom location (not GPS)
        let useGPS = UserDefaults.standard.bool(forKey: "Breezy.useGPSLocation")
        
        if !useGPS, let savedLocationData = UserDefaults.standard.data(forKey: "Breezy.selectedLocation"),
           let savedLocation = try? JSONDecoder().decode(LocationData.self, from: savedLocationData) {
            // Restore custom location
            Task {
                // Check if cached data is still valid for this location
                loadCacheIfValid()
                
                // If cache is valid and matches saved location, we're done
                if let cached = weather, cached.location.city == savedLocation.city {
                    return
                }
                
                // Otherwise fetch fresh data for saved location
                await fetchWeather(for: savedLocation, isManualRefresh: false)
            }
            return
        }
        
        // Using GPS location - check cache first
        loadCacheIfValid()
        
        // If we have valid cached data, stop here
        if weather != nil {
            return
        }
        
        // Otherwise fetch GPS location
        Task {
            do {
                let location = try await locationHelper.requestLocationAndGetData()
                await fetchWeather(for: location, isManualRefresh: false)
            } catch {
                self.error = "Could not determine your location"
            }
        }
    }
    
    // MARK: - Weather Fetching
    
    func fetchWeather(for location: LocationData, saveToCache: Bool = true, isManualRefresh: Bool = false) async {
        self.isLoading = true
        self.error = nil
        self.currentLocation = location
        
        let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        
        do {
            let weather = try await weatherService.weather(for: clLocation)
            let hourly = weather.hourlyForecast
            let daily = weather.dailyForecast
            
            let cityName = location.city
            
            // Get timezone for the location
            let geocoder = CLGeocoder()
            let placemarks = try? await geocoder.reverseGeocodeLocation(clLocation)
            let tz = placemarks?.first?.timeZone ?? TimeZone.current
            
            // Get current temperature
            let (tempValue, feelsValue) = getCurrentTemperatures(from: weather.currentWeather)
            let symbol = temperatureUnit.symbol
            let tempRaw = String(format: "%.0f°%@", tempValue, symbol)
            let feelsRaw = String(format: "%.0f°%@", feelsValue, symbol)
            
            let cond = WeatherConditionConverter.description(from: weather.currentWeather.condition)
            
            // Get today's high/low
            let (highTemp, lowTemp) = getTodayHighLow(from: daily)
            
            // Parse hourly forecast for today (every 3 hours for display)
            let todayHourlyForecast = parseHourlyForecast(from: hourly, timeZone: tz)
            
            // Parse ALL hours for drag interpolation
            let allHoursData = parseAllHourlyForecast(from: hourly)
            
            // Parse daily forecast (10 days)
            let dailyForecastArray = parseDailyForecast(from: daily, hourly: hourly, timeZone: tz)
            
            // Extract additional metrics
            let metrics = extractMetrics(from: weather.currentWeather, daily: daily, timeZone: tz)
            
            let emoji = WeatherIconHelper.emoji(for: cond)
            
            var updatedLocation = LocationData(
                city: cityName,
                latitude: location.latitude,
                longitude: location.longitude
            )
            updatedLocation.timezoneIdentifier = tz.identifier
            
            let info = WeatherInfo(
                location: updatedLocation,
                temperature: tempRaw,
                feelsLike: feelsRaw,
                highTemp: highTemp,
                lowTemp: lowTemp,
                condition: cond,
                emoji: emoji,
                hourlyForecast: todayHourlyForecast,
                allHourlyData: allHoursData,
                dailyForecast: dailyForecastArray,
                metrics: metrics,
                timezone: tz.identifier
            )
            self.weather = info
            if saveToCache { WeatherCache.save(info) }
            
            // Save widget data
            let todayRainChance = daily.forecast.first.map { Int($0.precipitationChance * 100) }
            
            // Extract accurate condition/daylight for widget icons
            let isDaylight = weather.currentWeather.isDaylight
            let conditionCode = weather.currentWeather.condition.description
            
            saveWidgetData(
                cityName: cityName,
                tempRaw: tempRaw,
                cond: cond,
                emoji: emoji,
                highTemp: highTemp,
                lowTemp: lowTemp,
                todayHourlyForecast: todayHourlyForecast,
                metrics: metrics,
                rainChance: todayRainChance.map { "\($0)%" },
                conditionCode: conditionCode,
                isDaylight: isDaylight
            )
            
            // Check for minute precipitation alerts (with cooldown built-in)
            notificationManager.checkMinutePrecipitation(weather: info)
            
            // Handle notifications - never on manual refresh or app startup
            let locationChanged = previousWeather?.location.city != location.city
            
            if !isManualRefresh && shouldTriggerNotifications(oldWeather: previousWeather, newWeather: info, locationChanged: locationChanged) {
                handleNotifications(newWeather: info, oldWeather: previousWeather, locationChanged: locationChanged)
            } else {
                // Still schedule daily forecast (doesn't send immediate notification)
                notificationManager.scheduleDailyForecast(weather: info, temperatureUnit: temperatureUnit)
            }
            
            // Update previous weather for change detection
            previousWeather = info
            
            RecentlyViewedStore.add(updatedLocation)
        } catch {
            self.error = "Failed to fetch weather: \(error.localizedDescription)"
        }
        self.isLoading = false
    }
    
    func fetchHistoricalWeather(for date: Date, slot: Int = 1) async {
        guard let location = currentLocation else { return }
        
        self.historicalLoading = true
        self.historicalError = nil
        if slot == 1 {
            self.historicalWeather = nil
        } else {
            self.historicalWeather2 = nil
        }
        
        let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        
        do {
            // WeatherKit historical fetch requires requesting specific collections with start/end dates
            let endDate = Calendar.current.date(byAdding: .day, value: 1, to: date)!
            
            // Fetch Daily and Hourly separately for the date range
            let dailyCollection = try await weatherService.weather(for: clLocation, including: .daily(startDate: date, endDate: endDate))
            let hourlyCollection = try await weatherService.weather(for: clLocation, including: .hourly(startDate: date, endDate: endDate))
            
            // Get timezone
            let geocoder = CLGeocoder()
            let placemarks = try? await geocoder.reverseGeocodeLocation(clLocation)
            let tz = placemarks?.first?.timeZone ?? TimeZone.current
            
            // Ensure we have data
            guard let dayWeather = dailyCollection.first else {
                throw NSError(domain: "Breezy", code: 404, userInfo: [NSLocalizedDescriptionKey: "No historical data found"])
            }
            
            // Parse High/Low
            let (highTemp, lowTemp) = getDayHighLow(from: dayWeather)
            
            // Parse Hourly
            // Convert to Forecast<HourWeather> wrapper to reuse existing parser or parse manually?
            // Existing parser 'parseHourlyForecast(from:timeZone:)' takes 'Forecast<HourWeather>'
            // We can just parse manually here for simplicity as the object types match (HourWeather)
            
            var hourlyResults: [HourlyForecast] = []
            let calendar = Calendar.current
            
            for hour in hourlyCollection {
                let hourInt = calendar.component(.hour, from: hour.date)
                // Filter every 3 hours or show all? Let's show all for detail in retro view
                
                let tempRaw: Double
                if temperatureUnit == .fahrenheit {
                    tempRaw = hour.temperature.converted(to: .fahrenheit).value
                } else {
                    tempRaw = hour.temperature.converted(to: .celsius).value
                }
                
                let weatherDesc = WeatherConditionConverter.description(from: hour.condition)
                let timeDisplay = DateFormatterHelper.formatHour(hourInt)
                
                hourlyResults.append(HourlyForecast(
                    time: timeDisplay,
                    temperatureRaw: tempRaw,
                    condition: weatherDesc,
                    emoji: WeatherIconHelper.emoji(for: weatherDesc),
                    hourValue: hourInt,
                    precipitationChance: hour.precipitationChance,
                    windSpeed: "", // Not simplified for this view
                    windDirection: "", 
                    uvIndex: Int(hour.uvIndex.value)
                ))
            }
            
            // Representative Condition (from DayWeather)
            let cond = WeatherConditionConverter.description(from: dayWeather.condition)
            let emoji = WeatherIconHelper.emoji(for: cond)
            
            // Representative Temperature
            let symbol = temperatureUnit.symbol
            let tempValue = temperatureUnit == .fahrenheit ? dayWeather.highTemperature.converted(to: .fahrenheit).value : dayWeather.highTemperature.converted(to: .celsius).value
            let tempRaw = String(format: "%.0f°%@", tempValue, symbol)
            
            // --- POPULATE DETAILED METRICS FOR TIME MACHINE V2 ---
            
            // Wind
            let windSpeedVal = windSpeedUnit == .milesPerHour ? dayWeather.wind.speed.converted(to: .milesPerHour).value : dayWeather.wind.speed.converted(to: .metersPerSecond).value
            let windSpeedStr = String(format: "%.0f %@", windSpeedVal, windSpeedUnit.symbol)
            let windDir = dayWeather.wind.direction.value
            let windCard = WindDirectionHelper.cardinalDirection(from: windDir)
            
            // UV
            // DayWeather usually has uvIndex (Quantity<UnitGradient>) or we can take max from hourly if needed.
            // DayWeather.uvIndex is available in newer WeatherKit, but fallback to 0 if not.
            let uvIndex = Int(dayWeather.uvIndex.value)
            let uvCategory = UVIndexHelper.category(for: uvIndex)
            
            // Sun times
            let sunriseStr = dayWeather.sun.sunrise.map { DateFormatterHelper.formatTime($0, timeZone: tz) }
            let sunsetStr = dayWeather.sun.sunset.map { DateFormatterHelper.formatTime($0, timeZone: tz) }
            
            // Precip
            let precipChance = String(format: "%.0f%%", dayWeather.precipitationChance * 100)
            
            // Humidity (DayWeather has average humidity usually, or use hourly)
            // Let's use the humidity from the hourly forecast roughly at noon as a proxy or average
            // Actually DayWeather doesn't expose humidity directly in all versions. 
            // We'll take the first hour (midnight) or noon. Let's take noon (12:00)
            let noonHour = hourlyCollection.first { calendar.component(.hour, from: $0.date) == 12 } ?? hourlyCollection.first
            let humidityVal = Int((noonHour?.humidity ?? 0) * 100)
            
            // Pressure
            let pressureVal = pressureUnit == .inchesOfMercury ? (noonHour?.pressure.converted(to: .inchesOfMercury).value ?? 0) : (noonHour?.pressure.converted(to: .hectopascals).value ?? 0)
            let pressureStr = String(format: "%.0f %@", pressureVal, pressureUnit.symbol)
            
            let metrics = WeatherMetrics(
                uvIndex: uvIndex,
                uvIndexCategory: uvCategory,
                airQuality: nil, // Historical AQI is hard to get
                pressure: pressureStr,
                visibility: nil, // Not critical
                dewPoint: nil,
                humidity: humidityVal,
                windDirection: windDir,
                windDirectionCardinal: windCard,
                windSpeed: windSpeedStr,
                rainChance: precipChance,
                cloudCover: nil,
                sunrise: sunriseStr,
                sunset: sunsetStr
            )
            
            let info = WeatherInfo(
                location: location,
                temperature: tempRaw,
                feelsLike: "", 
                highTemp: highTemp,
                lowTemp: lowTemp,
                condition: cond,
                emoji: emoji,
                hourlyForecast: hourlyResults,
                allHourlyData: [],
                dailyForecast: [],
                metrics: metrics,
                timezone: tz.identifier
            )
            
            // Assign to appropriate slot
            if slot == 1 {
                self.historicalWeather = info
            } else {
                self.historicalWeather2 = info
            }
            
        } catch {
            print("Historical Fetch Error: \(error)")
            self.historicalError = "Historical data is generally only available from August 2021 onwards for most locations."
        }
        
        self.historicalLoading = false
    }
    
    // MARK: - Historical Range (for Charts)
    
    func fetchHistoricalRange(startDate: Date, endDate: Date) async {
        guard let location = currentLocation else { return }
        
        self.historicalLoading = true
        self.historicalError = nil
        self.historicalRange = []
        
        let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        
        do {
            // Fetch daily weather for the range
            let dailyCollection = try await weatherService.weather(for: clLocation, including: .daily(startDate: startDate, endDate: endDate))
            
            var dataPoints: [HistoricalDataPoint] = []
            
            for dayWeather in dailyCollection {
                // Extract temperature
                let tempValue = temperatureUnit == .fahrenheit ? 
                    dayWeather.highTemperature.converted(to: .fahrenheit).value : 
                    dayWeather.highTemperature.converted(to: .celsius).value
                
                let highValue = temperatureUnit == .fahrenheit ? 
                    dayWeather.highTemperature.converted(to: .fahrenheit).value : 
                    dayWeather.highTemperature.converted(to: .celsius).value
                
                let lowValue = temperatureUnit == .fahrenheit ? 
                    dayWeather.lowTemperature.converted(to: .fahrenheit).value : 
                    dayWeather.lowTemperature.converted(to: .celsius).value
                
                let condition = WeatherConditionConverter.description(from: dayWeather.condition)
                
                dataPoints.append(HistoricalDataPoint(
                    date: dayWeather.date,
                    temperature: tempValue,
                    high: highValue,
                    low: lowValue,
                    condition: condition
                ))
            }
            
            self.historicalRange = dataPoints
            
        } catch {
            print("Historical Range Fetch Error: \(error)")
            self.historicalError = "Unable to load historical chart data."
        }
        
        self.historicalLoading = false
    }
    
    // MARK: - Compare Mode
    
    func compareWithCurrent(historicalDate: Date) -> WeatherComparison? {
        guard let current = weather, let past = historicalWeather else {
            return nil
        }
        
        return WeatherComparison(current: current, past: past)
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
    
    private func parseHourlyForecast(from hourlyForecast: Forecast<HourWeather>, timeZone: TimeZone) -> [HourlyForecast] {
        var forecasts: [HourlyForecast] = []
        
        // Get today's date range (start of today to start of tomorrow) in the LOCATION'S timezone
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        
        // Filter to only today's hours
        let todayHours = hourlyForecast.forecast.filter { hour in
            hour.date >= today && hour.date < tomorrow
        }
        
        // Sort by date and only include every 3 hours starting from 12 AM
        let sortedHours = todayHours.sorted { $0.date < $1.date }
        
        for hour in sortedHours {
            let hourInt = calendar.component(.hour, from: hour.date)
            
            // Only show every 3 hours (0, 3, 6, 9, 12, 15, 18, 21)
            guard hourInt % 3 == 0 else { continue }
            
            let tempRaw: Double
            if temperatureUnit == .fahrenheit {
                tempRaw = hour.temperature.converted(to: .fahrenheit).value
            } else {
                tempRaw = hour.temperature.converted(to: .celsius).value
            }
            
            let weatherDesc = WeatherConditionConverter.description(from: hour.condition)
            let timeDisplay = DateFormatterHelper.formatHour(hourInt)
            let emoji = WeatherIconHelper.emoji(for: weatherDesc)
            
            // Extract additional hourly data
            let precipitationChance = hour.precipitationChance
            let windSpeed = getHourlyWindSpeed(from: hour)
            let windDirection = getHourlyWindDirection(from: hour)
            let uvIndex = Int(hour.uvIndex.value)
            
            forecasts.append(HourlyForecast(
                time: timeDisplay,
                temperatureRaw: tempRaw,
                condition: weatherDesc,
                emoji: emoji,
                hourValue: hourInt,
                precipitationChance: precipitationChance,
                windSpeed: windSpeed,
                windDirection: windDirection,
                uvIndex: uvIndex
            ))
        }
        return forecasts
    }
    
    private func parseAllHourlyForecast(from hourlyForecast: Forecast<HourWeather>) -> [HourlyForecast] {
        var forecasts: [HourlyForecast] = []
        
        // Get all 24 hours of today (12 AM to 11 PM)
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        
        // Filter to today's hours
        let relevantHours = hourlyForecast.forecast.filter { hour in
            hour.date >= startOfToday && hour.date < endOfToday
        }
        
        // Sort by date
        let sortedHours = relevantHours.sorted { $0.date < $1.date }
        
        for hour in sortedHours {
            let hourInt = calendar.component(.hour, from: hour.date)
            
            let tempRaw: Double
            if temperatureUnit == .fahrenheit {
                tempRaw = hour.temperature.converted(to: .fahrenheit).value
            } else {
                tempRaw = hour.temperature.converted(to: .celsius).value
            }
            
            let weatherDesc = WeatherConditionConverter.description(from: hour.condition)
            let timeDisplay = DateFormatterHelper.formatHour(hourInt)
            let emoji = WeatherIconHelper.emoji(for: weatherDesc)
            
            // Extract additional hourly data
            let precipitationChance = hour.precipitationChance
            let windSpeed = getHourlyWindSpeed(from: hour)
            let windDirection = getHourlyWindDirection(from: hour)
            let uvIndex = Int(hour.uvIndex.value)
            
            forecasts.append(HourlyForecast(
                time: timeDisplay,
                temperatureRaw: tempRaw,
                condition: weatherDesc,
                emoji: emoji,
                hourValue: hourInt,
                precipitationChance: precipitationChance,
                windSpeed: windSpeed,
                windDirection: windDirection,
                uvIndex: uvIndex
            ))
        }
        return forecasts
    }
    
    private func parseDailyForecast(from daily: Forecast<DayWeather>, hourly: Forecast<HourWeather>, timeZone: TimeZone) -> [DailyForecast] {
        var dailyForecastArray: [DailyForecast] = []
        
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        
        for (index, day) in daily.forecast.prefix(10).enumerated() {
            // Get hourly data for this day
            let dayStart = calendar.startOfDay(for: day.date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            
            let dayHourlyData = hourly.forecast.filter { hour in
                hour.date >= dayStart && hour.date < dayEnd
            }.sorted { $0.date < $1.date } // Sort by time
            
            let dayHourlyForecast = dayHourlyData.compactMap { hour -> HourlyForecast? in
                let hourInt = calendar.component(.hour, from: hour.date)
                // Only show every 3 hours (0, 3, 6, 9, 12, 15, 18, 21)
                guard hourInt % 3 == 0 else { return nil }
                
                let tempRaw: Double
                if temperatureUnit == .fahrenheit {
                    tempRaw = hour.temperature.converted(to: .fahrenheit).value
                } else {
                    tempRaw = hour.temperature.converted(to: .celsius).value
                }
                
                let weatherDesc = WeatherConditionConverter.description(from: hour.condition)
                let timeDisplay = DateFormatterHelper.formatHour(hourInt)
                
                // Extract additional hourly data
                let precipitationChance = hour.precipitationChance
                let windSpeed = getHourlyWindSpeed(from: hour)
                let windDirection = getHourlyWindDirection(from: hour)
                let uvIndex = Int(hour.uvIndex.value)
                
                return HourlyForecast(
                    time: timeDisplay,
                    temperatureRaw: tempRaw,
                    condition: weatherDesc,
                    emoji: WeatherIconHelper.emoji(for: weatherDesc),
                    hourValue: hourInt,
                    precipitationChance: precipitationChance,
                    windSpeed: windSpeed,
                    windDirection: windDirection,
                    uvIndex: uvIndex
                )
            }
            
            // All hourly data for detailed view (every hour)
            let allDayHourlyData = dayHourlyData.map { hour -> HourlyForecast in
                let hourInt = calendar.component(.hour, from: hour.date)
                
                let tempRaw: Double
                if temperatureUnit == .fahrenheit {
                    tempRaw = hour.temperature.converted(to: .fahrenheit).value
                } else {
                    tempRaw = hour.temperature.converted(to: .celsius).value
                }
                
                let weatherDesc = WeatherConditionConverter.description(from: hour.condition)
                let timeDisplay = DateFormatterHelper.formatHour(hourInt)
                
                return HourlyForecast(
                    time: timeDisplay,
                    temperatureRaw: tempRaw,
                    condition: weatherDesc,
                    emoji: WeatherIconHelper.emoji(for: weatherDesc),
                    hourValue: hourInt,
                    precipitationChance: hour.precipitationChance,
                    windSpeed: getHourlyWindSpeed(from: hour),
                    windDirection: getHourlyWindDirection(from: hour),
                    uvIndex: Int(hour.uvIndex.value)
                )
            }
            
            let dayName = index == 0 ? "Today" : DateFormatterHelper.formatDayName(day.date, timeZone: timeZone)
            let dateStr = DateFormatterHelper.dateFormatter.string(from: day.date)
            
            let (high, low) = getDayHighLow(from: day)
            let condition = WeatherConditionConverter.description(from: day.condition)
            let chanceOfRain = Int(day.precipitationChance * 100)
            let windSpeed = getWindSpeed(from: day)
            
            let sunriseDate = day.sun.sunrise ?? day.date
            let sunsetDate = day.sun.sunset ?? day.date
            let sunrise = DateFormatterHelper.formatTime(sunriseDate, timeZone: timeZone)
            let sunset = DateFormatterHelper.formatTime(sunsetDate, timeZone: timeZone)
            
            // Extract moon phase and moon times
            let moonPhase = extractMoonPhase(from: day)
            let moonrise = day.moon.moonrise.map { DateFormatterHelper.formatTime($0, timeZone: timeZone) }
            let moonset = day.moon.moonset.map { DateFormatterHelper.formatTime($0, timeZone: timeZone) }
            
            dailyForecastArray.append(DailyForecast(
                date: dateStr,
                dayName: dayName,
                highTemp: high,
                lowTemp: low,
                condition: condition,
                emoji: WeatherIconHelper.emoji(for: condition),
                chanceOfRain: "\(chanceOfRain)%",
                windSpeed: windSpeed,
                humidity: nil,
                sunrise: sunrise,
                sunset: sunset,
                sunriseDate: sunriseDate,
                sunsetDate: sunsetDate,
                moonPhase: moonPhase,
                moonrise: moonrise,
                moonset: moonset,
                hourlyData: dayHourlyForecast,
                allHourlyData: allDayHourlyData
            ))
        }
        
        return dailyForecastArray
    }
    
    private func getDayHighLow(from day: DayWeather) -> (high: String, low: String) {
        if temperatureUnit == .fahrenheit {
            let maxF = day.highTemperature.converted(to: .fahrenheit).value
            let minF = day.lowTemperature.converted(to: .fahrenheit).value
            return (String(format: "%.0f°", maxF), String(format: "%.0f°", minF))
        } else {
            let maxC = day.highTemperature.converted(to: .celsius).value
            let minC = day.lowTemperature.converted(to: .celsius).value
            return (String(format: "%.0f°", maxC), String(format: "%.0f°", minC))
        }
    }
    
    private func getWindSpeed(from day: DayWeather) -> String {
        if temperatureUnit == .fahrenheit {
            let windMph = day.wind.speed.converted(to: .milesPerHour).value
            return String(format: "%.0f mph", windMph)
        } else {
            let windKph = day.wind.speed.converted(to: .kilometersPerHour).value
            return String(format: "%.0f km/h", windKph)
        }
    }
    
    private func getHourlyWindSpeed(from hour: HourWeather) -> String {
        if temperatureUnit == .fahrenheit {
            let windMph = hour.wind.speed.converted(to: .milesPerHour).value
            return String(format: "%.0f mph", windMph)
        } else {
            let windKph = hour.wind.speed.converted(to: .kilometersPerHour).value
            return String(format: "%.0f km/h", windKph)
        }
    }
    
    private func getHourlyWindDirection(from hour: HourWeather) -> String? {
        let direction = hour.wind.direction.value
        return WindDirectionHelper.cardinalDirection(from: direction)
    }
    
    private func extractMetrics(from currentWeather: CurrentWeather, daily: Forecast<DayWeather>, timeZone: TimeZone) -> WeatherMetrics {
        // UV Index
        let uvIndex = Int(currentWeather.uvIndex.value)
        let uvCategory = UVIndexHelper.category(for: uvIndex)
        
        // Air Quality (WeatherKit may not provide this in CurrentWeather, set to nil for now)
        // Air quality is typically available through separate API calls or may not be available
        let airQuality: AirQuality? = nil
        
        // Pressure
        let pressureValue = currentWeather.pressure.converted(to: .hectopascals).value
        let convertedPressure = pressureUnit.convert(pressureValue)
        let pressure = String(format: "%.0f %@", convertedPressure, pressureUnit.displayName)
        
        // Visibility
        let visibilityValueMeters = currentWeather.visibility.converted(to: .meters).value
        let convertedVisibility = visibilityUnit.convert(visibilityValueMeters)
        let visibility = String(format: "%.1f %@", convertedVisibility, visibilityUnit.symbol)
        
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
        
        // Humidity
        let humidity = Int(currentWeather.humidity * 100)
        
        // Wind Direction
        let windDirection = currentWeather.wind.direction
        let windDirectionDegrees = windDirection.converted(to: .degrees).value
        let windCardinal = WindDirectionHelper.cardinalDirection(from: windDirectionDegrees)
        
        // Wind Speed
        let windSpeedValueMPS = currentWeather.wind.speed.converted(to: .metersPerSecond).value
        let convertedWindSpeed = windSpeedUnit.convert(windSpeedValueMPS)
        let windSpeed = String(format: "%.0f %@", convertedWindSpeed, windSpeedUnit.displayName)
        
        // Additional Metrics derived from Daily Forecast (Today)
        var rainChance: String?
        var cloudCover: String?
        var sunrise: String?
        var sunset: String?
        
        if let today = daily.forecast.first {
            rainChance = String(format: "%.0f%%", today.precipitationChance * 100)
            if let rise = today.sun.sunrise {
                sunrise = DateFormatterHelper.formatTime(rise, timeZone: timeZone)
            }
            if let set = today.sun.sunset {
                sunset = DateFormatterHelper.formatTime(set, timeZone: timeZone)
            }
        }
        
        cloudCover = String(format: "%.0f%%", currentWeather.cloudCover * 100)
        
        return WeatherMetrics(
            uvIndex: uvIndex,
            uvIndexCategory: uvCategory,
            airQuality: airQuality,
            pressure: pressure,
            visibility: visibility,
            dewPoint: dewPoint,
            humidity: humidity,
            windDirection: windDirectionDegrees,
            windDirectionCardinal: windCardinal,
            windSpeed: windSpeed,
            rainChance: rainChance,
            cloudCover: cloudCover,
            sunrise: sunrise,
            sunset: sunset
        )
    }
    
    private func extractMoonPhase(from day: DayWeather) -> MoonPhase? {
        // WeatherKit provides moon phase information through moon events
        // Moon illumination is typically 0.0 to 1.0, but we need to calculate it from moon phase
        // For now, we'll use a simple calculation based on the date
        let calendar = Calendar.current
        let daysSinceNewMoon = calendar.dateComponents([.day], from: calendar.startOfDay(for: day.date), to: Date()).day ?? 0
        let illumination = abs(sin(Double(daysSinceNewMoon % 29) / 29.0 * 2 * .pi))
        
        let phaseName = MoonPhaseHelper.phaseName(from: illumination)
        let icon = MoonPhaseHelper.icon(for: phaseName)
        
        return MoonPhase(
            phase: phaseName,
            illumination: illumination,
            icon: icon
        )
    }
    
    private func saveWidgetData(
        cityName: String,
        tempRaw: String,
        cond: String,
        emoji: String,
        highTemp: String?,
        lowTemp: String?,
        todayHourlyForecast: [HourlyForecast],
        metrics: WeatherMetrics,
        rainChance: String?,
        conditionCode: String = "Clear",
        isDaylight: Bool = true
    ) {
        // Get current hour
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: Date())
        
        // Filter to next 24 hours
        // Since todayHourlyForecast now contains "next 24 hours", we can just use it directly
        // But we still want to filter out any that might be in the past (just in case)
        let futureHours = todayHourlyForecast.filter { hour in
            // Filter out past hours, but keep current hour
            // Note: Since todayHourlyForecast is already filtered to >= now, this is just a safety check
            return true
        }
        
        // Build widget hourly forecast: start with "Now", then next 2 hours for small/medium,
        // but we save 12 hours so the timeline provider can use them.
        var widgetHourly: [WidgetWeatherData.WidgetHourlyForecast] = []
        
        // Always add "Now" as first entry with current weather
        widgetHourly.append(WidgetWeatherData.WidgetHourlyForecast(
            time: "Now",
            temperature: tempRaw,
            emoji: emoji,
            condition: cond
        ))
        
        // Add the next 12 hours (so widget can simulate future weather)
        for hour in futureHours.prefix(12) {
            // Skip if it's the same as current hour (already added as "Now")
            if hour.hourValue == currentHour {
                continue
            }
            widgetHourly.append(WidgetWeatherData.WidgetHourlyForecast(
                time: hour.time,
                temperature: self.formattedTemperature(hour.temperatureRaw),
                emoji: hour.emoji,
                condition: hour.condition
            ))
        }
        
        // Save all collected hours (Now + 12 future hours)
        let finalWidgetHourly = widgetHourly
        
        let widgetData = WidgetWeatherData(
            city: cityName,
            temperature: tempRaw,
            condition: cond,
            emoji: emoji,
            highTemp: highTemp,
            lowTemp: lowTemp,
            hourlyForecast: finalWidgetHourly,
            timestamp: Date(),
            useMinimalistIcons: useMinimalistIcons,
            uvIndex: metrics.uvIndex,
            pressure: metrics.pressure,
            windSpeed: metrics.windSpeed,
            rainChance: rainChance,
            latitude: currentLocation?.latitude,
            longitude: currentLocation?.longitude,
            conditionCode: conditionCode,
            isDaylight: isDaylight,
            minTemp: lowTemp,
            maxTemp: highTemp,
            humidity: metrics.humidity.map { "\($0)%" },
            visibility: metrics.visibility,
            dailyForecast: []  // Will be populated by widget's own fetch
        )
        
        
        WidgetDataStore.save(widgetData)
        
        // Save Unit Preferences to App Group so Widget can use them for background updates
        
        // Save Unit Preferences to App Group so Widget can use them for background updates
        if let defaults = UserDefaults(suiteName: "group.com.breezy.weather") {
            defaults.set(temperatureUnit.rawValue, forKey: "Breezy.temperatureUnit")
            defaults.set(windSpeedUnit.rawValue, forKey: "Breezy.windSpeedUnit")
            defaults.set(pressureUnit.rawValue, forKey: "Breezy.pressureUnit")
            defaults.set(visibilityUnit.rawValue, forKey: "Breezy.visibilityUnit")
            defaults.set(precipitationUnit.rawValue, forKey: "Breezy.precipitationUnit")
        }
    }
    
    // MARK: - Notifications
    
    private func shouldTriggerNotifications(oldWeather: WeatherInfo?, newWeather: WeatherInfo, locationChanged: Bool) -> Bool {
        // Don't trigger on first fetch (app startup)
        guard oldWeather != nil else { return false }
        
        // Only trigger on background location changes (significant location change)
        // This indicates the user moved to a new location, not a manual refresh
        if locationChanged {
            return true
        }
        
        // Don't trigger on regular weather updates - only on actual events
        // Severe weather, rain, and UV alerts will be checked but only fire if conditions are met
        // The daily forecast is scheduled separately and doesn't need this check
        return false
    }
    
    private func parseTemperature(_ tempString: String) -> Double {
        let cleaned = tempString.replacingOccurrences(of: "°", with: "")
            .replacingOccurrences(of: temperatureUnit.symbol, with: "")
            .replacingOccurrences(of: "[^0-9.-]", with: "", options: .regularExpression)
        return Double(cleaned) ?? 0.0
    }
    
    private func handleNotifications(newWeather: WeatherInfo, oldWeather: WeatherInfo?, locationChanged: Bool) {
        // Schedule daily forecast (doesn't send immediate notification)
        notificationManager.scheduleDailyForecast(weather: newWeather, temperatureUnit: temperatureUnit)
        
        // Notification Checks
        notificationManager.checkSevereWeather(weather: newWeather) // Assuming fetchedCounty is available in this scope
        notificationManager.checkRainAlert(weather: newWeather)
        notificationManager.checkUVAlert(weather: newWeather)
        notificationManager.checkMinutePrecipitation(weather: newWeather)
        
        // New notification checks
        notificationManager.checkTemperatureChange(weather: newWeather, temperatureUnit: self.temperatureUnit)
        notificationManager.checkWindAlert(weather: newWeather)
        notificationManager.checkPrecipitationProbability(weather: newWeather)
    }
    
    private func syncWatchContext() {
        WatchSessionManager.shared.updateContext(
            useMinimalistIcons: useMinimalistIcons,
            typography: typography,
            visibleMetrics: visibleMetrics,
            temperatureUnit: temperatureUnit,
            windSpeedUnit: windSpeedUnit,
            pressureUnit: pressureUnit,
            visibilityUnit: visibilityUnit,
            themeMode: themeMode,
            presetTheme: selectedPresetThemeName,
            currentTheme: currentTheme,
            customTheme: customTheme,
            mapStyle: mapStyle
        )
    }
}

