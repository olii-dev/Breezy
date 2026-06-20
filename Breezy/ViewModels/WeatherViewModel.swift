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
import WidgetKit

@MainActor
class WeatherViewModel: ObservableObject {
    struct RainTimingSummary: Equatable {
        let headline: String
        let detail: String?
        let isActive: Bool
    }

    struct ForecastNarrativeSummary: Equatable {
        let headline: String
        let detail: String?
    }
    
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
            self?.syncWatchContext()
        }
        
        // Observe cloud sync completions to update UI
        NotificationCenter.default.addObserver(forName: .cloudDataReconciled, object: nil, queue: .main) { [weak self] _ in
            self?.reloadSettingsFromPersistence()
        }
        
        // Send initial state delayed to ensure properties are loaded (backup)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self.syncWatchContext()
            
            // Fetch initial attribution
            self.attribution = await weatherProviderManager.attribution()
        }
    }
    
    private func reloadSettingsFromPersistence() {
        shouldFollowGPS = UserDefaults.standard.bool(forKey: "Breezy.shouldFollowGPS")
        useMinimalistIcons = UserDefaults.standard.object(forKey: "Breezy.useMinimalistIcons") as? Bool ?? true
        showWindChartInDayDetail = UserDefaults.standard.object(forKey: "Breezy.showWindChartInDayDetail") as? Bool ?? true
        showUVChartInDayDetail = UserDefaults.standard.object(forKey: "Breezy.showUVChartInDayDetail") as? Bool ?? true
        showQuickStatsInDayDetail = UserDefaults.standard.object(forKey: "Breezy.showQuickStatsInDayDetail") as? Bool ?? true
        showHourlyBreakdownInDayDetail = UserDefaults.standard.object(forKey: "Breezy.showHourlyBreakdownInDayDetail") as? Bool ?? true
        showPrecipitationChartInDayDetail = UserDefaults.standard.object(forKey: "Breezy.showPrecipitationChartInDayDetail") as? Bool ?? true
        showHourlyChartsInDayDetail = UserDefaults.standard.object(forKey: "Breezy.showHourlyChartsInDayDetail") as? Bool ?? true
        showSunMoonInDayDetail = UserDefaults.standard.object(forKey: "Breezy.showSunMoonInDayDetail") as? Bool ?? true
        themeMode = ThemeMode(rawValue: UserDefaults.standard.string(forKey: "Breezy.themeMode") ?? "") ?? .auto
        selectedPresetThemeName = UserDefaults.standard.string(forKey: "Breezy.presetTheme") ?? "Cotton Candy"
        weatherSourceRaw = WeatherSourceStore.selectedSource.rawValue
        
        if let data = UserDefaults.standard.data(forKey: "Breezy.customTheme"),
           let theme = try? JSONDecoder().decode(WeatherTheme.self, from: data) {
            customThemes = [theme]
            selectedCustomThemeID = theme.id
        }

        syncSelectedCustomThemeToSharedDefaults()
        
        objectWillChange.send()
    }
    @Published var currentLocation: LocationData?
    @Published var weather: WeatherInfo?
    @Published var attribution: AppWeatherAttribution?
    @Published var historicalWeather: WeatherInfo? // Time Machine Data - Date 1
    @Published var historicalWeather2: WeatherInfo? // Time Machine Data - Date 2 (for comparison)
    @Published var historicalRange: [HistoricalDataPoint] = [] // For Charts (deprecated)
    @Published var isLoading = false
    @Published var historicalLoading = false
    @Published var error: String?
    @Published var historicalError: String?
    @Published var isUsingCachedFallback = false

    @AppStorage("Breezy.temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.celsius.rawValue
    @AppStorage("Breezy.windSpeedUnit") private var windSpeedUnitRaw: String = WindSpeedUnit.metersPerSecond.rawValue
    @AppStorage("Breezy.pressureUnit") private var pressureUnitRaw: String = PressureUnit.hectopascals.rawValue
    @AppStorage("Breezy.visibilityUnit") private var visibilityUnitRaw: String = VisibilityUnit.kilometers.rawValue
    @AppStorage("Breezy.precipitationUnit") private var precipitationUnitRaw: String = PrecipitationUnit.millimeters.rawValue
    @AppStorage("Breezy.dateFormat") private var dateFormatRaw: String = DateFormat.short.rawValue
    @AppStorage("Breezy.cacheDurationMinutes") var cacheDurationMinutes: Int = 30
    @AppStorage("Breezy.glassOpacity") var glassOpacity: Double = 0.35
    @AppStorage(WeatherSourceStore.storageKey) private var weatherSourceRaw: String = WeatherSource.weatherKit.rawValue
    @AppStorage(RadarPrecipitationSource.storageKey) private var radarPrecipitationSourceRaw: String = RadarPrecipitationSource.rainViewer.rawValue


    
    @Published var shouldFollowGPS: Bool = {
        if UserDefaults.standard.object(forKey: "Breezy.shouldFollowGPS") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "Breezy.shouldFollowGPS")
    }() {
        didSet {
            UserDefaults.standard.set(shouldFollowGPS, forKey: "Breezy.shouldFollowGPS")
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
            objectWillChange.send()
        }
    }
    
    // Day Detail View Settings
    @Published var showWindChartInDayDetail: Bool = UserDefaults.standard.object(forKey: "Breezy.showWindChartInDayDetail") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showWindChartInDayDetail, forKey: "Breezy.showWindChartInDayDetail")
            objectWillChange.send()
        }
    }
    
    @Published var showUVChartInDayDetail: Bool = UserDefaults.standard.object(forKey: "Breezy.showUVChartInDayDetail") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showUVChartInDayDetail, forKey: "Breezy.showUVChartInDayDetail")
            objectWillChange.send()
        }
    }
    
    @Published var showQuickStatsInDayDetail: Bool = UserDefaults.standard.object(forKey: "Breezy.showQuickStatsInDayDetail") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showQuickStatsInDayDetail, forKey: "Breezy.showQuickStatsInDayDetail")
            objectWillChange.send()
        }
    }
    
    @Published var showHourlyBreakdownInDayDetail: Bool = UserDefaults.standard.object(forKey: "Breezy.showHourlyBreakdownInDayDetail") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showHourlyBreakdownInDayDetail, forKey: "Breezy.showHourlyBreakdownInDayDetail")
            objectWillChange.send()
        }
    }
    
    @Published var showPrecipitationChartInDayDetail: Bool = UserDefaults.standard.object(forKey: "Breezy.showPrecipitationChartInDayDetail") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showPrecipitationChartInDayDetail, forKey: "Breezy.showPrecipitationChartInDayDetail")
            objectWillChange.send()
        }
    }
    
    @Published var showHourlyChartsInDayDetail: Bool = UserDefaults.standard.object(forKey: "Breezy.showHourlyChartsInDayDetail") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showHourlyChartsInDayDetail, forKey: "Breezy.showHourlyChartsInDayDetail")
            objectWillChange.send()
        }
    }
    
    @Published var showSunMoonInDayDetail: Bool = UserDefaults.standard.object(forKey: "Breezy.showSunMoonInDayDetail") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showSunMoonInDayDetail, forKey: "Breezy.showSunMoonInDayDetail")
            objectWillChange.send()
        }
    }

    // Theme Settings
    @Published var themeMode: ThemeMode = ThemeMode(rawValue: UserDefaults.standard.string(forKey: "Breezy.themeMode") ?? "") ?? .auto {
        didSet {
            UserDefaults.standard.set(themeMode.rawValue, forKey: "Breezy.themeMode")
            // Sync to App Group
            if let defaults = UserDefaults(suiteName: "group.com.breezy.weather") {
                defaults.set(themeMode.rawValue, forKey: "Breezy.themeMode")
                defaults.set(Date().timeIntervalSince1970, forKey: "Breezy.lastUpdate") // Force update
            }
            // Trigger widget reload
            WidgetCenter.shared.reloadAllTimelines()
            
            syncWatchContext()
            objectWillChange.send()
        }
    }
    
    @Published var selectedPresetThemeName: String = UserDefaults.standard.string(forKey: "Breezy.presetTheme") ?? "Cotton Candy" {
        didSet {
            UserDefaults.standard.set(selectedPresetThemeName, forKey: "Breezy.presetTheme")
            // Sync to App Group
            if let defaults = UserDefaults(suiteName: "group.com.breezy.weather") {
                defaults.set(selectedPresetThemeName, forKey: "Breezy.presetTheme")
            }
            // Trigger widget reload
            WidgetCenter.shared.reloadAllTimelines()
            
            syncWatchContext()
            objectWillChange.send()
        }
    }
    
    // Custom theme persistence using the new Codable color helper
    @Published var customThemes: [WeatherTheme] = {
        if let data = UserDefaults.standard.data(forKey: "Breezy.customThemes"),
           let themes = try? JSONDecoder().decode([WeatherTheme].self, from: data) {
            return themes
        }
        return []
    }() {
        didSet {
            if let data = try? JSONEncoder().encode(customThemes) {
                UserDefaults.standard.set(data, forKey: "Breezy.customThemes")
                if let defaults = UserDefaults(suiteName: "group.com.breezy.weather") {
                    defaults.set(data, forKey: "Breezy.customThemes")
                }
            }
            syncSelectedCustomThemeToSharedDefaults()
            WidgetCenter.shared.reloadAllTimelines()
            syncWatchContext()
            objectWillChange.send()
        }
    }
    
    @Published var selectedCustomThemeID: String? = UserDefaults.standard.string(forKey: "Breezy.selectedCustomThemeID") {
        didSet {
            UserDefaults.standard.set(selectedCustomThemeID, forKey: "Breezy.selectedCustomThemeID")
            if let defaults = UserDefaults(suiteName: "group.com.breezy.weather") {
                defaults.set(selectedCustomThemeID, forKey: "Breezy.selectedCustomThemeID")
            }
            syncSelectedCustomThemeToSharedDefaults()
            WidgetCenter.shared.reloadAllTimelines()
            syncWatchContext()
            objectWillChange.send()
        }
    }
    
    var customTheme: WeatherTheme {
        if let id = selectedCustomThemeID, let theme = customThemes.first(where: { $0.id == id }) {
            return theme
        }
        if let first = customThemes.first {
            return first
        }
        return WeatherTheme.defaultCustom
    }

    private func syncSelectedCustomThemeToSharedDefaults() {
        guard let defaults = UserDefaults(suiteName: "group.com.breezy.weather") else { return }

        if let data = try? JSONEncoder().encode(customThemes) {
            defaults.set(data, forKey: "Breezy.customThemes")
        }

        if let selected = customThemes.first(where: { $0.id == selectedCustomThemeID }) ?? customThemes.first,
           let selectedData = try? JSONEncoder().encode(selected) {
            defaults.set(selectedData, forKey: "Breezy.selectedCustomTheme")
            defaults.set(selectedData, forKey: "Breezy.customTheme")
        } else {
            defaults.removeObject(forKey: "Breezy.selectedCustomTheme")
            defaults.removeObject(forKey: "Breezy.customTheme")
        }

        defaults.set(Date().timeIntervalSince1970, forKey: "Breezy.lastUpdate")
    }
    
    // Computed property to resolve the current active theme

    private let weatherProviderManager = WeatherProviderManager.shared
    private let notificationManager = NotificationManager.shared
    private var previousWeather: WeatherInfo?
    private var latestWeatherFetchID = UUID()

    var lastUpdatedDate: Date? {
        guard let timestamp = weather?.timestamp else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    var isShowingStaleWeather: Bool {
        guard let weather else { return false }
        let age = Date().timeIntervalSince1970 - weather.timestamp
        let cacheAgeLimit = Double(cacheDurationMinutes * 60)
        let cachedFallbackBannerDelay: TimeInterval = 5 * 60

        if age > cacheAgeLimit {
            return true
        }

        // Avoid warning about "saved weather" when the app has just restored a very
        // fresh payload from disk. If the data stays cached for a while, we surface it.
        return isUsingCachedFallback && age > cachedFallbackBannerDelay
    }

    var staleWeatherMessage: String? {
        if isShowingStaleWeather, isUsingCachedFallback, let error, weather != nil {
            return error
        }

        guard isShowingStaleWeather else { return nil }
        return "Showing saved weather until Breezy refreshes again."
    }
    
    var temperatureUnit: TemperatureUnit {
        get { TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius }
        set { 
            temperatureUnitRaw = newValue.rawValue
            // Sync to App Group
            if let defaults = UserDefaults(suiteName: "group.com.breezy.weather") {
                defaults.set(newValue.rawValue, forKey: "Breezy.temperatureUnit")
                WidgetCenter.shared.reloadAllTimelines()
            }
            syncWatchContext()
            objectWillChange.send()
        }
    }
    
    var windSpeedUnit: WindSpeedUnit {
        get { WindSpeedUnit(rawValue: windSpeedUnitRaw) ?? .metersPerSecond }
        set { 
            windSpeedUnitRaw = newValue.rawValue
            // Sync to App Group
            if let defaults = UserDefaults(suiteName: "group.com.breezy.weather") {
                defaults.set(newValue.rawValue, forKey: "Breezy.windSpeedUnit")
                WidgetCenter.shared.reloadAllTimelines()
            }
            syncWatchContext()
            objectWillChange.send()
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

    var weatherSource: WeatherSource {
        get { WeatherSource(rawValue: weatherSourceRaw) ?? .weatherKit }
        set {
            weatherSourceRaw = newValue.rawValue
            WeatherSourceStore.selectedSource = newValue
            attribution = nil
            historicalWeather = nil
            historicalWeather2 = nil
            historicalRange = []
            WidgetCenter.shared.reloadAllTimelines()
            syncWatchContext()
            objectWillChange.send()
        }
    }

    var providerCapabilities: WeatherProviderCapabilities {
        weatherSource.capabilities
    }

    private var formattingContext: WeatherFormattingContext {
        WeatherFormattingContext(
            temperatureUnit: temperatureUnit,
            windSpeedUnit: windSpeedUnit,
            pressureUnit: pressureUnit,
            visibilityUnit: visibilityUnit,
            precipitationUnit: precipitationUnit
        )
    }

    var rainTimingSummary: RainTimingSummary? {
        guard let weather else { return nil }
        let now = Date()

        if let minuteForecast = weather.metrics?.minuteForecast,
           let summary = minuteRainTimingSummary(from: minuteForecast, now: now) {
            return summary
        }

        let hourlySource = weather.allHourlyData ?? weather.hourlyForecast
        return hourlyRainTimingSummary(from: hourlySource, now: now)
    }

    var rainSoonLabel: String? {
        rainTimingSummary?.headline
    }

    var rainSoonDetail: String? {
        rainTimingSummary?.detail
    }

    var severeWeatherAssessment: SevereWeatherAssessment? {
        guard let weather else { return nil }
        let assessment = NotificationManager.severeWeatherAssessment(for: weather)
        return assessment.isSevere ? assessment : nil
    }

    var forecastNarrative: String? {
        forecastNarrativeSummary?.headline
    }

    var forecastNarrativeSummary: ForecastNarrativeSummary? {
        guard let weather else { return nil }
        return narrativeSummary(for: Array(weather.dailyForecast.prefix(10)))
    }

    private func minuteRainTimingSummary(from minuteForecast: [MinuteForecast], now: Date) -> RainTimingSummary? {
        let relevantMinutes = minuteForecast
            .filter { $0.time >= now.addingTimeInterval(-60) }
            .sorted { $0.time < $1.time }

        guard !relevantMinutes.isEmpty else { return nil }

        let currentMinute = relevantMinutes.first { $0.time >= now.addingTimeInterval(-120) } ?? relevantMinutes[0]
        let isCurrentlyRaining = isMeaningfulPrecipitation(currentMinute) && abs(currentMinute.time.timeIntervalSince(now)) <= 180

        if isCurrentlyRaining {
            let startIndex = relevantMinutes.firstIndex(where: { isMeaningfulPrecipitation($0) }) ?? 0
            let rainBlock = relevantMinutes[startIndex...]
            if let firstDryMinute = rainBlock.first(where: { !isMeaningfulPrecipitation($0) }) {
                let minutesLeft = max(1, Int(ceil(firstDryMinute.time.timeIntervalSince(now) / 60)))
                let detail = minutesLeft <= 2 ? "Should ease shortly." : "Likely easing in \(minutesLeft) min."
                return RainTimingSummary(headline: "Rain right now", detail: detail, isActive: true)
            }

            return RainTimingSummary(headline: "Rain right now", detail: "Rain may linger through the next hour.", isActive: true)
        }

        guard let startIndex = relevantMinutes.firstIndex(where: { $0.time > now && isMeaningfulPrecipitation($0) }) else {
            return nil
        }

        let startMinute = relevantMinutes[startIndex]
        let minutesUntil = max(1, Int(ceil(startMinute.time.timeIntervalSince(now) / 60)))
        let block = relevantMinutes[startIndex...].prefix(while: { isMeaningfulPrecipitation($0) })
        let duration = max(1, block.count)

        let detail: String
        if duration <= 10 {
            detail = "Looks brief once it starts."
        } else if duration <= 25 {
            detail = "Likely to last around \(duration) min."
        } else {
            detail = "Looks like a longer wet stretch once it starts."
        }

        return RainTimingSummary(headline: "Rain in \(minutesUntil) min", detail: detail, isActive: false)
    }

    private func hourlyRainTimingSummary(from hours: [HourlyForecast], now: Date) -> RainTimingSummary? {
        guard !hours.isEmpty else { return nil }

        let currentHour = Calendar.current.component(.hour, from: now)

        for hour in hours.prefix(8) {
            let chance = hour.precipitationChance ?? 0
            let condition = (hour.condition ?? "").lowercased()
            let hasRainSignal = chance >= 0.35 || condition.contains("rain") || condition.contains("drizzle") || condition.contains("shower")

            guard hasRainSignal else { continue }

            var delta = hour.hourValue - currentHour
            if delta < 0 { delta += 24 }

            if delta == 0 {
                return RainTimingSummary(headline: "Rain likely this hour", detail: "Keep an eye out over the next hour.", isActive: false)
            }

            if delta == 1 {
                return RainTimingSummary(headline: "Rain within ~1 hour", detail: "Showers look more likely by \(hour.time).", isActive: false)
            }

            if delta <= 6 {
                return RainTimingSummary(headline: "Rain later today", detail: "Best chance is around \(hour.time).", isActive: false)
            }
        }

        return nil
    }

    private func isMeaningfulPrecipitation(_ minute: MinuteForecast) -> Bool {
        minute.precipitationChance >= 0.35 || minute.precipitationIntensity > 0.02
    }

    private func narrativeSummary(for forecast: [DailyForecast]) -> ForecastNarrativeSummary {
        guard !forecast.isEmpty else {
            return ForecastNarrativeSummary(
                headline: "Mostly steady weather ahead.",
                detail: "No major swings stand out across the next several days."
            )
        }

        if let severeDay = forecast.first(where: { isSevereCondition($0.condition) }) {
            let severeChance = percentageValue(from: severeDay.chanceOfRain)
            return ForecastNarrativeSummary(
                headline: "More active weather arrives \(dayLabel(for: severeDay.dayName)) with \(severeDay.condition.lowercased()).",
                detail: severeChance.map { "That is the sharpest turn in the next 10 days, with rain odds around \($0)% and a better chance of disruptive conditions than the surrounding days." } ?? "That looks like the sharpest shift in the next 10 days, so it is worth checking again as the day gets closer."
            )
        }

        let rainyDays = forecast.filter { day in
            let chance = percentageValue(from: day.chanceOfRain) ?? 0
            return chance >= 60 || containsRainLanguage(day.condition)
        }

        if let firstRainyDay = rainyDays.first {
            let wettestDay = rainyDays.max(by: { (percentageValue(from: $0.chanceOfRain) ?? 0) < (percentageValue(from: $1.chanceOfRain) ?? 0) })
            let peakChance = wettestDay.flatMap { percentageValue(from: $0.chanceOfRain) } ?? 0

            if rainyDays.count >= 2,
               let lastRainyDay = consecutiveTail(from: forecast, startingAt: firstRainyDay, matching: { day in
                   let chance = percentageValue(from: day.chanceOfRain) ?? 0
                   return chance >= 60 || containsRainLanguage(day.condition)
               }),
               firstRainyDay.dayName != lastRainyDay.dayName {
                return ForecastNarrativeSummary(
                    headline: "A wetter stretch runs from \(dayLabel(for: firstRainyDay.dayName)) to \(dayLabel(for: lastRainyDay.dayName)).",
                    detail: peakChance > 0 ? "Confidence is strongest around \(dayLabel(for: wettestDay?.dayName ?? firstRainyDay.dayName)), where rain chances climb near \(peakChance)%. Expect fewer dry breaks during that run than elsewhere in the outlook." : "Those days carry the most persistent rain signal in the next 10 days, with fewer dry breaks showing up in between."
                )
            }

            return ForecastNarrativeSummary(
                headline: "Rain chances build \(dayLabel(for: firstRainyDay.dayName)).",
                detail: peakChance > 0 ? "That is the clearest wet-weather window right now, with the strongest signal topping out near \(peakChance)% while the rest of the outlook stays comparatively quieter." : "The rest of the forecast stays comparatively quieter, so that is the main wet-weather window right now."
            )
        }

        let windyDays = forecast.filter {
            guard let speed = parseWindSpeed($0.windSpeed) else { return false }
            return speed >= 20
        }

        if let windiestDay = windyDays.max(by: { (parseWindSpeed($0.windSpeed) ?? 0) < (parseWindSpeed($1.windSpeed) ?? 0) }) {
            let peakWind = Int(round(parseWindSpeed(windiestDay.windSpeed) ?? 0))
            return ForecastNarrativeSummary(
                headline: "Wind picks up \(dayLabel(for: windiestDay.dayName)), so it may feel rougher outdoors.",
                detail: peakWind > 0 ? "The breeziest part of the stretch looks close to \(peakWind) mph, which could make exposed spots feel noticeably less settled even if rain stays limited." : "Even without much rain, that part of the forecast may feel less settled thanks to the stronger breeze."
            )
        }

        let highs = forecast.map { parseNarrativeTemperature($0.highTemp) }
        if let firstHigh = highs.first, let lastHigh = highs.last {
            let delta = lastHigh - firstHigh
            let targetDay = forecast[min(forecast.count - 1, 4)].dayName

            if delta >= 4 {
                return ForecastNarrativeSummary(
                    headline: "A gradual warm-up builds through \(dayLabel(for: targetDay)).",
                    detail: "Highs rise by about \(delta)° from the start of the outlook, so it should feel progressively milder instead of changing all at once."
                )
            }

            if delta <= -4 {
                return ForecastNarrativeSummary(
                    headline: "Cooler air settles in by \(dayLabel(for: targetDay)).",
                    detail: "Highs slide by about \(abs(delta))° across the stretch, with the coolest part arriving later rather than showing up immediately."
                )
            }
        }

        if let warmestDay = forecast.max(by: { parseNarrativeTemperature($0.highTemp) < parseNarrativeTemperature($1.highTemp) }),
           let coolestDay = forecast.min(by: { parseNarrativeTemperature($0.highTemp) < parseNarrativeTemperature($1.highTemp) }),
           warmestDay.dayName != coolestDay.dayName,
           abs(parseNarrativeTemperature(warmestDay.highTemp) - parseNarrativeTemperature(coolestDay.highTemp)) >= 4 {
            let spread = abs(parseNarrativeTemperature(warmestDay.highTemp) - parseNarrativeTemperature(coolestDay.highTemp))
            return ForecastNarrativeSummary(
                headline: "\(dayLabel(for: warmestDay.dayName).capitalized) looks warmest, while \(dayLabel(for: coolestDay.dayName)) should be coolest.",
                detail: "That puts roughly a \(spread)° gap between the warmest and coolest highs, while the rest of the forecast still looks fairly even day to day."
            )
        }

        return ForecastNarrativeSummary(
            headline: "Mostly steady weather through the next few days.",
            detail: "No single rain, wind, or temperature swing dominates the next 10 days right now, so the broader pattern still looks fairly settled."
        )
    }

    private func consecutiveTail(from forecast: [DailyForecast], startingAt startDay: DailyForecast, matching: (DailyForecast) -> Bool) -> DailyForecast? {
        guard let startIndex = forecast.firstIndex(of: startDay) else { return nil }
        var tail = startDay

        for day in forecast.dropFirst(startIndex + 1) {
            guard matching(day) else { break }
            tail = day
        }

        return tail
    }

    private func dayLabel(for dayName: String) -> String {
        dayName == "Today" ? "today" : dayName
    }

    private func percentageValue(from string: String?) -> Int? {
        guard let string else { return nil }
        return Int(string.replacingOccurrences(of: "%", with: ""))
    }

    private func parseNarrativeTemperature(_ string: String) -> Int {
        Int(string.replacingOccurrences(of: "[^0-9-]", with: "", options: .regularExpression)) ?? 0
    }

    private func containsRainLanguage(_ condition: String) -> Bool {
        let lowercased = condition.lowercased()
        return lowercased.contains("rain") || lowercased.contains("shower") || lowercased.contains("drizzle")
    }

    private func isSevereCondition(_ condition: String) -> Bool {
        let lowercased = condition.lowercased()
        let severeKeywords = ["thunderstorm", "strong storms", "tropical storm", "hail", "squall", "blizzard", "heavy snow", "heavy rain"]
        return severeKeywords.contains { lowercased.contains($0) }
    }

    private func parseWindSpeed(_ windString: String?) -> Double? {
        guard let windString else { return nil }
        let lowercased = windString.lowercased()
        let isKmh = lowercased.contains("km/h")
        let cleaned = lowercased
            .replacingOccurrences(of: "mph", with: "")
            .replacingOccurrences(of: "km/h", with: "")
            .replacingOccurrences(of: "knots", with: "")
            .replacingOccurrences(of: "m/s", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "[^0-9.-]", with: "", options: .regularExpression)

        guard let value = Double(cleaned) else { return nil }

        if isKmh { return value * 0.621371 }
        if lowercased.contains("m/s") { return value * 2.23694 }
        if lowercased.contains("knots") { return value * 1.15078 }
        return value
    }
    
    @Published var appearanceMode: AppearanceMode = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "Breezy.appearanceMode") ?? "") ?? .auto {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "Breezy.appearanceMode")
            // Sync to App Group
            if let defaults = UserDefaults(suiteName: "group.com.breezy.weather") {
                defaults.set(appearanceMode.rawValue, forKey: "Breezy.appearanceMode")
                WidgetCenter.shared.reloadAllTimelines()
            }
            syncWatchContext()
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
        case satellite = "Satellite"
        
        var id: String { rawValue }
    }
    
    @Published var mapStyle: RadarMapStyle = RadarMapStyle(rawValue: UserDefaults.standard.string(forKey: "Breezy.mapStyle") ?? "") ?? .standard {
        didSet {
            UserDefaults.standard.set(mapStyle.rawValue, forKey: "Breezy.mapStyle")
            objectWillChange.send()
        }
    }

    var radarPrecipitationSource: RadarPrecipitationSource {
        get { RadarPrecipitationSource(rawValue: radarPrecipitationSourceRaw) ?? .rainViewer }
        set {
            radarPrecipitationSourceRaw = newValue.rawValue
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

    func formattedPrecipitationAmount(_ amount: Double, decimals: Int = 1) -> String {
        let converted = precipitationUnit.convert(amount)
        let format = "%.\(decimals)f %@"
        return String(format: format, converted, precipitationUnit.symbol)
    }

    func formattedWindSpeedValue(_ value: Double, decimals: Int = 0) -> String {
        let format = "%.\(decimals)f %@"
        return String(format: format, value, windSpeedUnit.displayName)
    }
    
    func weatherIcon(for condition: String) -> String {
        WeatherIconHelper.minimalistIcon(for: condition)
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

    func savedManualLocation() -> LocationData? {
        guard let savedLocationData = UserDefaults.standard.data(forKey: "Breezy.selectedLocation") else {
            return nil
        }

        return try? JSONDecoder().decode(LocationData.self, from: savedLocationData)
    }

    func preferredLocationForCurrentSelection() -> LocationData? {
        if shouldFollowGPS {
            return currentLocation
        }

        return savedManualLocation() ?? currentLocation
    }

    func loadCacheIfValid(expectedLocation: LocationData? = nil) {
        if let cached = WeatherCache.load(source: weatherSource) {
            let age = Date().timeIntervalSince1970 - cached.timestamp
            if age <= Double(cacheDurationMinutes * 60) {
                if let expectedLocation, cached.location.id != expectedLocation.id {
                    return
                }

                self.weather = cached
                self.currentLocation = expectedLocation ?? cached.location
                self.isUsingCachedFallback = true
                
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
                    metrics: cached.metrics ?? WeatherMetrics(uvIndex: nil, uvIndexCategory: nil, airQuality: nil, marine: nil, pressure: nil, visibility: nil, dewPoint: nil, humidity: nil, windDirection: nil, windDirectionCardinal: nil, windSpeed: nil, windGust: nil, rainChance: nil, todayRainfall: nil, todayMaxRainIntensity: nil, cloudCover: nil, sunrise: nil, sunset: nil, minuteForecast: nil),
                    rainChance: rainChance,
                    rainAmount: cached.metrics?.todayRainfall,
                    dailyForecast: cached.dailyForecast
                )
            } else {
                WeatherCache.clear(source: weatherSource)
                self.isUsingCachedFallback = false
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
        let useGPS = shouldFollowGPS
        
        if !useGPS, let savedLocation = savedManualLocation() {
            // Restore custom location
            Task {
                // Check if cached data is still valid for this location
                loadCacheIfValid(expectedLocation: savedLocation)
                
                // If cache is valid and matches saved location, we're done
                if let cached = weather, cached.location.id == savedLocation.id {
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
                self.error = "We couldn't determine your location yet. Choose a city manually or try again."
            }
        }
    }
    
    // MARK: - Weather Fetching
    
    func fetchWeather(for location: LocationData, saveToCache: Bool = true, isManualRefresh: Bool = false) async {
        // Prevent duplicate automatic requests, but always let a manual refresh win.
        if isLoading && !isManualRefresh {
            if currentLocation?.id == location.id && weather != nil {
                return
            }
        }

        let requestID = UUID()
        latestWeatherFetchID = requestID
        self.isLoading = true
        self.error = nil
        self.currentLocation = location

        do {
            let result = try await weatherProviderManager.fetchWeather(for: location, formatting: formattingContext)
            guard latestWeatherFetchID == requestID else { return }
            let info = result.weather
            self.weather = info
            self.isUsingCachedFallback = false
            if saveToCache {
                WeatherCache.save(info, source: weatherSource)
            }
            self.attribution = result.attribution
            
            saveWidgetData(
                cityName: info.location.city,
                tempRaw: info.temperature,
                cond: info.condition,
                emoji: info.emoji,
                highTemp: info.highTemp,
                lowTemp: info.lowTemp,
                todayHourlyForecast: info.hourlyForecast,
                metrics: info.metrics ?? WeatherMetrics(uvIndex: nil, uvIndexCategory: nil, airQuality: nil, marine: nil, pressure: nil, visibility: nil, dewPoint: nil, humidity: nil, windDirection: nil, windDirectionCardinal: nil, windSpeed: nil, windGust: nil, rainChance: nil, todayRainfall: nil, todayMaxRainIntensity: nil, cloudCover: nil, sunrise: nil, sunset: nil, minuteForecast: nil),
                rainChance: info.dailyForecast.first?.chanceOfRain,
                rainAmount: info.metrics?.todayRainfall,
                conditionCode: result.conditionCode ?? info.condition,
                isDaylight: result.isDaylight,
                dailyForecast: info.dailyForecast
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
            
            // Refresh attribution periodically or on fetch
            if attribution == nil {
                self.attribution = await weatherProviderManager.attribution()
            }
        } catch {
            guard latestWeatherFetchID == requestID else { return }
            self.error = userFriendlyError(error)
        }
        if latestWeatherFetchID == requestID {
            self.isLoading = false
        }
    }
    
    private func userFriendlyError(_ error: Error) -> String {
        let nsError = error as NSError
        
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return "No internet connection. Pull to refresh when online."
            case NSURLErrorTimedOut:
                return "Request timed out. Pull to try again."
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                return "Unable to reach weather service. Please try again later."
            default:
                return "Unable to load weather. Pull to refresh."
            }
        }
        
        if nsError.domain == CLError.errorDomain {
            switch CLError.Code(rawValue: nsError.code) {
            case .denied:
                return "Location access denied. Enable in Settings."
            case .locationUnknown:
                return "Unable to determine location. Try again."
            default:
                return "Location error. Please try again."
            }
        }
        
        return "Unable to load weather. Pull to refresh."
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
        
        do {
            let info = try await weatherProviderManager.fetchHistoricalWeather(for: location, date: date, formatting: formattingContext)
            if slot == 1 {
                self.historicalWeather = info
            } else {
                self.historicalWeather2 = info
            }
        } catch {
            print("Historical Fetch Error: \(error)")
            let nsError = error as NSError
            if let description = nsError.userInfo[NSLocalizedDescriptionKey] as? String,
               !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.historicalError = description
            } else {
                self.historicalError = providerCapabilities.historicalAvailabilityDescription
            }
        }
        
        self.historicalLoading = false
    }
    
    // MARK: - Historical Range (for Charts)
    
    func fetchHistoricalRange(startDate: Date, endDate: Date) async {
        guard let location = currentLocation else { return }
        
        self.historicalLoading = true
        self.historicalError = nil
        self.historicalRange = []
        
        do {
            self.historicalRange = try await weatherProviderManager.fetchHistoricalRange(
                for: location,
                startDate: startDate,
                endDate: endDate,
                formatting: formattingContext
            )
            
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
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else {
            return []
        }
        
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
            let precipitationAmount = hour.precipitationAmount.value // mm
            let windSpeed = getHourlyWindSpeed(from: hour)
            let windGust = getHourlyWindGust(from: hour)
            let windDirection = getHourlyWindDirection(from: hour)
            let uvIndex = Int(hour.uvIndex.value)
            let humidity = Int(hour.humidity * 100)
            
            forecasts.append(HourlyForecast(
                sourceDate: hour.date,
                time: timeDisplay,
                temperatureRaw: tempRaw,
                condition: weatherDesc,
                emoji: emoji,
                hourValue: hourInt,
                precipitationChance: precipitationChance,
                precipitationAmount: precipitationAmount,
                windSpeed: windSpeed,
                windGust: windGust,
                windDirection: windDirection,
                uvIndex: uvIndex,
                humidity: humidity
            ))
        }
        return forecasts
    }
    
    private func parseAllHourlyForecast(from hourlyForecast: Forecast<HourWeather>, timeZone: TimeZone) -> [HourlyForecast] {
        var forecasts: [HourlyForecast] = []
        
        // Get all 24 hours of today (12 AM to 11 PM)
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let startOfToday = calendar.startOfDay(for: Date())
        guard let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            return []
        }
        
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
            let precipitationAmount = hour.precipitationAmount.value // mm
            let windSpeed = getHourlyWindSpeed(from: hour)
            let windGust = getHourlyWindGust(from: hour)
            let windDirection = getHourlyWindDirection(from: hour)
            let uvIndex = Int(hour.uvIndex.value)
            let humidity = Int(hour.humidity * 100)
            
            forecasts.append(HourlyForecast(
                sourceDate: hour.date,
                time: timeDisplay,
                temperatureRaw: tempRaw,
                condition: weatherDesc,
                emoji: emoji,
                hourValue: hourInt,
                precipitationChance: precipitationChance,
                precipitationAmount: precipitationAmount,
                windSpeed: windSpeed,
                windGust: windGust,
                windDirection: windDirection,
                uvIndex: uvIndex,
                humidity: humidity
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
            guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
                continue
            }
            
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
                let windGust = getHourlyWindGust(from: hour)
                let windDirection = getHourlyWindDirection(from: hour)
                let uvIndex = Int(hour.uvIndex.value)
                
                return HourlyForecast(
                    sourceDate: hour.date,
                    time: timeDisplay,
                    temperatureRaw: tempRaw,
                    condition: weatherDesc,
                    emoji: WeatherIconHelper.emoji(for: weatherDesc),
                    hourValue: hourInt,
                    precipitationChance: precipitationChance,
                    precipitationAmount: hour.precipitationAmount.value,
                    windSpeed: windSpeed,
                    windGust: windGust,
                    windDirection: windDirection,
                    uvIndex: uvIndex,
                    humidity: Int(hour.humidity * 100)
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
                    sourceDate: hour.date,
                    time: timeDisplay,
                    temperatureRaw: tempRaw,
                    condition: weatherDesc,
                    emoji: WeatherIconHelper.emoji(for: weatherDesc),
                    hourValue: hourInt,
                    precipitationChance: hour.precipitationChance,
                    precipitationAmount: hour.precipitationAmount.value,
                    windSpeed: getHourlyWindSpeed(from: hour),
                    windGust: getHourlyWindGust(from: hour),
                    windDirection: getHourlyWindDirection(from: hour),
                    uvIndex: Int(hour.uvIndex.value),
                    humidity: Int(hour.humidity * 100)
                )
            }

            let fallbackHourlyData: [HourlyForecast]
            if !dayHourlyForecast.isEmpty {
                fallbackHourlyData = dayHourlyForecast
            } else if !allDayHourlyData.isEmpty {
                fallbackHourlyData = allDayHourlyData
            } else {
                fallbackHourlyData = []
            }

            let detailedHourlyData = allDayHourlyData.isEmpty ? nil : allDayHourlyData
            let humidityValues = allDayHourlyData.compactMap(\.humidity)
            let averageHumidity = humidityValues.isEmpty ? nil : Int(round(Double(humidityValues.reduce(0, +)) / Double(humidityValues.count)))
            
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

#if DEBUG
            print("📊 Day \(dayName): summary hours=\(fallbackHourlyData.count), detailed hours=\(allDayHourlyData.count)")
#endif
            
            dailyForecastArray.append(DailyForecast(
                date: dateStr,
                dayName: dayName,
                highTemp: high,
                lowTemp: low,
                condition: condition,
                emoji: WeatherIconHelper.emoji(for: condition),
                chanceOfRain: "\(chanceOfRain)%",
                windSpeed: windSpeed,
                windDirection: day.wind.direction.value,
                windDirectionCardinal: WindDirectionHelper.cardinalDirection(from: day.wind.direction.value),
                humidity: averageHumidity.map { "\($0)%" },
                sunrise: sunrise,
                sunset: sunset,
                sunriseDate: sunriseDate,
                sunsetDate: sunsetDate,
                moonPhase: moonPhase,
                moonrise: moonrise,
                moonset: moonset,
                hourlyData: fallbackHourlyData,
                allHourlyData: detailedHourlyData
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
    
    private func getHourlyWindGust(from hour: HourWeather) -> Double? {
        guard let gust = hour.wind.gust else { return nil }
        if temperatureUnit == .fahrenheit {
            return gust.converted(to: .milesPerHour).value
        } else {
            return gust.converted(to: .kilometersPerHour).value
        }
    }
    
    private func getHourlyWindGustString(from hour: HourWeather) -> String? {
        guard let gust = hour.wind.gust else { return nil }
        if temperatureUnit == .fahrenheit {
            let gustMph = gust.converted(to: .milesPerHour).value
            return String(format: "%.0f mph", gustMph)
        } else {
            let gustKph = gust.converted(to: .kilometersPerHour).value
            return String(format: "%.0f km/h", gustKph)
        }
    }
    
    private func parseMinuteForecast(from minuteForecast: Forecast<MinuteWeather>?) -> [MinuteForecast] {
        guard let forecast = minuteForecast else { return [] }
        
        return forecast.forecast.map { minute in
            MinuteForecast(
                time: minute.date,
                precipitationChance: minute.precipitationChance,
                precipitationIntensity: minute.precipitationIntensity.value,
                isPrecipitating: minute.precipitationChance > 0
            )
        }
    }
    
    private func getHourlyWindDirection(from hour: HourWeather) -> String? {
        let direction = hour.wind.direction.value
        return WindDirectionHelper.cardinalDirection(from: direction)
    }
    
    private func extractMetrics(from currentWeather: CurrentWeather, daily: Forecast<DayWeather>, hourly: Forecast<HourWeather>, minuteForecast: Forecast<MinuteWeather>?, timeZone: TimeZone) -> WeatherMetrics {
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
        
        // Wind Gust - from current hour's forecast
        var windGust: String?
        if let currentHour = hourly.forecast.first(where: { $0.date >= Date() }) ?? hourly.forecast.first {
            windGust = getHourlyWindGustString(from: currentHour)
        }
        
        // Minute Forecast for next 60 minutes
        let minuteData = parseMinuteForecast(from: minuteForecast)
        
        // Rain Today - calculate from hourly forecast for today
        var todayRainfall: String?
        var todayMaxRainIntensity: String?
        
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        guard let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            return WeatherMetrics(
                uvIndex: uvIndex,
                uvIndexCategory: uvCategory,
                airQuality: airQuality,
                marine: nil,
                pressure: pressure,
                visibility: visibility,
                dewPoint: dewPoint,
                humidity: humidity,
                windDirection: windDirectionDegrees,
                windDirectionCardinal: windCardinal,
                windSpeed: windSpeed,
                windGust: windGust,
                rainChance: nil,
                todayRainfall: nil,
                todayMaxRainIntensity: nil,
                cloudCover: String(format: "%.0f%%", currentWeather.cloudCover * 100),
                sunrise: nil,
                sunset: nil,
                minuteForecast: minuteData
            )
        }
        
        let todayHours = hourly.forecast.filter { $0.date >= startOfToday && $0.date < endOfToday }
        
        if !todayHours.isEmpty {
            let totalPrecip = todayHours.reduce(0.0) { $0 + $1.precipitationAmount.value }
            let maxIntensity = todayHours.map { $0.precipitationAmount.value }.max() ?? 0
            
            let convertedTotal = precipitationUnit.convert(totalPrecip)
            let convertedMax = precipitationUnit.convert(maxIntensity)
            
            todayRainfall = String(format: "%.1f %@", convertedTotal, precipitationUnit.symbol)
            todayMaxRainIntensity = String(format: "%.1f %@/h", convertedMax, precipitationUnit.symbol)
        }
        
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
            marine: nil,
            pressure: pressure,
            visibility: visibility,
            dewPoint: dewPoint,
            humidity: humidity,
            windDirection: windDirectionDegrees,
            windDirectionCardinal: windCardinal,
            windSpeed: windSpeed,
            windGust: windGust,
            rainChance: rainChance,
            todayRainfall: todayRainfall,
            todayMaxRainIntensity: todayMaxRainIntensity,
            cloudCover: cloudCover,
            sunrise: sunrise,
            sunset: sunset,
            minuteForecast: minuteData
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
        rainAmount: String?,
        conditionCode: String = "Clear",
        isDaylight: Bool = true,
        dailyForecast: [DailyForecast]
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
                emoji: hour.emoji ?? "",
                condition: hour.condition ?? ""
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
            rainAmount: rainAmount,
            latitude: currentLocation?.latitude,
            longitude: currentLocation?.longitude,
            conditionCode: conditionCode,
            isDaylight: isDaylight,
            minTemp: lowTemp,
            maxTemp: highTemp,
            humidity: metrics.humidity.map { "\($0)%" },
            visibility: metrics.visibility,
            dailyForecast: dailyForecast.map { day in
                WidgetWeatherData.WidgetDailyForecast(
                    dayName: day.dayName,
                    highTemp: day.highTemp,
                    lowTemp: day.lowTemp,
                    condition: day.condition
                )
            },
            sunrise: nil,
            sunset: nil,
            moonPhase: nil,
            moonIllumination: nil,
            windDirectionDegrees: nil
        )
        
        
        WidgetDataStore.save(widgetData, source: weatherSource)
        
        // Save Unit Preferences to App Group so Widget can use them for background updates
        
        // Save Unit Preferences to App Group so Widget can use them for background updates
        if let defaults = UserDefaults(suiteName: "group.com.breezy.weather") {
            defaults.set(weatherSource.rawValue, forKey: WeatherSourceStore.storageKey)
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
        let theme: WeatherTheme
        switch themeMode {
        case .custom:
            theme = customTheme
        case .preset:
            if let preset = WeatherTheme.presets.first(where: { $0.name == selectedPresetThemeName }) {
                theme = preset.light
            } else {
                theme = WeatherTheme.defaultCustom
            }
        case .auto:
            let condition = weather?.condition ?? "Clear"
            theme = WeatherTheme.theme(for: condition, isDark: false)
        }

        WatchSessionManager.shared.updateContext(
            weatherSource: weatherSource,
            useMinimalistIcons: useMinimalistIcons,
            typography: typography,
            visibleMetrics: visibleMetrics,
            temperatureUnit: temperatureUnit,
            windSpeedUnit: windSpeedUnit,
            pressureUnit: pressureUnit,
            visibilityUnit: visibilityUnit,
            precipitationUnit: precipitationUnit,
            themeMode: themeMode,
            presetTheme: selectedPresetThemeName,
            currentTheme: theme,
            customTheme: customTheme,
            mapStyle: mapStyle,
            radarPrecipitationSource: radarPrecipitationSource
        )
    }
}
