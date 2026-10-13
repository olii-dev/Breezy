//
//  NotificationManager.swift
//  Breezy
//
//  Manages all weather notifications
//

import Foundation
import Combine
import UserNotifications
import CoreLocation
import os.log

struct SevereWeatherAssessment: Equatable {
    let isSevere: Bool
    let headline: String
    let detail: String
    let symbol: String
}

@MainActor
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    private let notificationCenter = UNUserNotificationCenter.current()
    private let alertState = AlertStateStore.shared
#if DEBUG
    private let logger = Logger(subsystem: "com.breezy.weather", category: "notifications")
#endif
    private var settings: NotificationSettings {
        get { UserDefaults.standard.notificationSettings }
        set { UserDefaults.standard.notificationSettings = newValue }
    }
    
    override init() {
        super.init()
        notificationCenter.delegate = self
        checkAuthorizationStatus()
    }
    
    // MARK: - Permission Management
    
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            await checkAuthorizationStatus()
            return granted
        } catch {
            return false
        }
    }
    
    func checkAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }
    
    private func checkAuthorizationStatus() {
        Task {
            await checkAuthorizationStatus()
        }
    }
    
    // MARK: - Quiet Hours
    
    private func isInQuietHours() -> Bool {
        settings.isQuietHours()
    }
    
    // MARK: - Sound Helper
    
    private func getSound(for notificationType: String) -> UNNotificationSound? {
        let soundOption: SoundOption
        switch notificationType {
        case "dailyForecast": soundOption = settings.dailyForecastSound
        case "severeWeather": soundOption = settings.severeWeatherSound
        case "rainAlert", "minuteRain", "rainCancelled": soundOption = settings.rainAlertSound
        case "uvAlert": soundOption = settings.uvAlertSound
        case "temperatureChange": soundOption = settings.temperatureChangeSound
        case "windAlert": soundOption = settings.windAlertSound
        case "precipitationProbability": soundOption = settings.precipitationProbabilitySound
        default: soundOption = .default
        }
        return soundOption.unSound
    }
    
    // MARK: - Notification Categories
    
    func registerNotificationCategories() {
        let viewAction = UNNotificationAction(
            identifier: "VIEW_ACTION",
            title: "View Details",
            options: [.foreground]
        )
        
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS_ACTION",
            title: "Dismiss",
            options: []
        )

        let snoozeRainAction = UNNotificationAction(
            identifier: "SNOOZE_RAIN_ACTION",
            title: "Snooze 30 min",
            options: []
        )
        
        let weatherAlertCategory = UNNotificationCategory(
            identifier: "WEATHER_ALERT",
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        let dailyForecastCategory = UNNotificationCategory(
            identifier: "DAILY_FORECAST",
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        let rainAlertCategory = UNNotificationCategory(
            identifier: "RAIN_ALERT",
            actions: [viewAction, snoozeRainAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        let uvAlertCategory = UNNotificationCategory(
            identifier: "UV_ALERT",
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        let temperatureChangeCategory = UNNotificationCategory(
            identifier: "TEMPERATURE_CHANGE",
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        let windAlertCategory = UNNotificationCategory(
            identifier: "WIND_ALERT",
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        let precipitationProbabilityCategory = UNNotificationCategory(
            identifier: "PRECIPITATION_PROBABILITY",
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        
        notificationCenter.setNotificationCategories([
            weatherAlertCategory,
            dailyForecastCategory,
            rainAlertCategory,
            uvAlertCategory,
            temperatureChangeCategory,
            windAlertCategory,
            precipitationProbabilityCategory
        ])
    }
    
    // MARK: - Rain Alert Snooze

    /// While set and in the future, rain alerts stay quiet.
    func snoozeRainAlerts(minutes: Int = 30) {
        alertState.update { $0.rainSnoozedUntil = Date().addingTimeInterval(TimeInterval(minutes) * 60) }
    }

    private func isRainAlertSnoozed() -> Bool {
        guard let until = alertState.state.rainSnoozedUntil else { return false }
        if until > Date() { return true }
        alertState.update { $0.rainSnoozedUntil = nil } // expired — clear it
        return false
    }

    // MARK: - Daily Forecast Notification

    /// Days of forecast scheduled ahead. Non-repeating triggers with baked content;
    /// every successful weather fetch cancels and refills the window, so the forecast
    /// keeps arriving for up to a week even if the app is never opened.
    private static let dailyForecastDaysAhead = 7

    func scheduleDailyForecast(weather: WeatherInfo, temperatureUnit: TemperatureUnit) {
        guard settings.dailyForecastEnabled else {
            cancelDailyForecast()
            return
        }

        guard authorizationStatus == .authorized else { return }

        // Reschedule off the main actor: inspecting pending requests is async.
        // Request identifiers are deterministic per (day, slot), so overlapping
        // reschedules converge instead of duplicating.
        Task {
            await removeAllPendingDailyForecasts()
            await addDailyForecastRequests(weather: weather, temperatureUnit: temperatureUnit)
        }
    }

    func cancelDailyForecast() {
        Task {
            await removeAllPendingDailyForecasts()
        }
    }

    /// Cancel every pending daily-forecast request regardless of which id scheme or
    /// settings config scheduled it, matched on category rather than id list.
    private func removeAllPendingDailyForecasts() async {
        let requests = await notificationCenter.pendingNotificationRequests()
        let ids = requests
            .filter { $0.content.categoryIdentifier == "DAILY_FORECAST" }
            .map(\.identifier)
        guard !ids.isEmpty else { return }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ids)
        #if DEBUG
        logger.debug("cancelled \(ids.count) pending daily forecast requests")
        #endif
    }

    private func addDailyForecastRequests(weather: WeatherInfo, temperatureUnit: TemperatureUnit) async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var scheduled = 0

        for dayOffset in 0..<Self.dailyForecastDaysAhead {
            guard let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }

            // Weekday restriction applies per scheduled day, not just today.
            if settings.onlyWeekdayForecast && calendar.isDateInWeekend(targetDay) { continue }

            for (slotIndex, time) in settings.dailyForecastTimes.enumerated() {
                var dateComponents = calendar.dateComponents([.year, .month, .day], from: targetDay)
                dateComponents.hour = time.hour
                dateComponents.minute = time.minute

                guard let fireDate = calendar.date(from: dateComponents), fireDate > Date() else { continue }

                let content = UNMutableNotificationContent()
                content.title = dailyForecastTitle(for: targetDay, dayOffset: dayOffset)
                content.body = formatDailyForecastBody(weather: weather, temperatureUnit: temperatureUnit, dayIndex: dayOffset)
                content.sound = getSound(for: "dailyForecast") ?? .default
                content.categoryIdentifier = "DAILY_FORECAST"
                content.userInfo = ["type": "dailyForecast"]

                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "dailyForecast_\(dayOffset)_\(slotIndex)",
                    content: content,
                    trigger: trigger
                )

                notificationCenter.add(request) { _ in }
                scheduled += 1
            }
        }

        #if DEBUG
        logger.debug("scheduled \(scheduled) daily forecast requests over \(Self.dailyForecastDaysAhead) days")
        #endif
    }

    private func dailyForecastTitle(for date: Date, dayOffset: Int) -> String {
        switch dayOffset {
        case 0: return "Today's Weather"
        case 1: return "Tomorrow's Weather"
        default:
            let weekday = Calendar.current.component(.weekday, from: date)
            return "\(Calendar.current.weekdaySymbols[weekday - 1])'s Weather"
        }
    }
    
    private func formatDailyForecastBody(weather: WeatherInfo, temperatureUnit: TemperatureUnit, dayIndex: Int = 0) -> String {
        let preferences = settings.dailyForecastContent
        var parts: [String] = []
        
        let daily: DailyForecast?
        if weather.dailyForecast.count > dayIndex {
            daily = weather.dailyForecast[dayIndex]
        } else {
            daily = weather.dailyForecast.first
        }
        
        // Add condition
        if preferences.includeCondition {
            if let condition = daily?.condition {
                parts.append(condition)
            } else {
                parts.append(weather.condition)
            }
        }
        
        // Add temperature range
        if preferences.includeTemperatureRange {
            if let d = daily {
                 parts.append("High: \(d.highTemp), Low: \(d.lowTemp)")
            } else if let h = weather.highTemp, let l = weather.lowTemp {
                 parts.append("High: \(h), Low: \(l)")
            }
        }
        
        // Add rain chance if significant
        if preferences.includeRainChance {
            if let d = daily,
               let rainChance = d.chanceOfRain,
               let rainValue = Int(rainChance.replacingOccurrences(of: "%", with: "")),
               rainValue >= 30 {
                parts.append("\(rainChance) rain")
            }
        }
        
        // Add UV warning if high
        if preferences.includeUVIndex {
            if dayIndex == 0, let uvIndex = weather.metrics?.uvIndex, uvIndex >= 7 {
                parts.append("High UV: \(uvIndex)")
            }
        }
        
        // Add wind if strong
        if preferences.includeWindSpeed {
            if dayIndex == 0,
               let windSpeed = weather.metrics?.windSpeed,
               let windValue = parseWindSpeed(windSpeed),
               windValue >= 20 {
                parts.append("Wind: \(windSpeed)")
            }
        }
        
        // Add humidity if requested
        if preferences.includeHumidity, let humidity = weather.metrics?.humidity {
            parts.append("Humidity: \(humidity)")
        }
        
        // Add feels like if requested
        if preferences.includeFeelsLike, let feelsLike = weather.feelsLike {
            parts.append("Feels like: \(feelsLike)")
        }
        
        // Add visibility if requested
        if preferences.includeVisibility, let visibility = weather.metrics?.visibility {
            parts.append("Visibility: \(visibility)")
        }
        
        return parts.joined(separator: " • ")
    }

    private func notificationSupplementaryDetails(
        for weather: WeatherInfo,
        preferences: NotificationContentPreference,
        limit: Int = 3
    ) -> [String] {
        var details: [String] = []
        let todayForecast = weather.dailyForecast.first

        if preferences.includeCondition {
            details.append(weather.condition)
        }

        if preferences.includeTemperatureRange {
            if let high = weather.highTemp, let low = weather.lowTemp {
                details.append("H: \(high), L: \(low)")
            } else {
                details.append("Temp: \(weather.temperature)")
            }
        }

        if preferences.includeHumidity, let humidity = weather.metrics?.humidity {
            details.append("Humidity: \(humidity)%")
        }

        if preferences.includeWindSpeed, let windSpeed = weather.metrics?.windSpeed {
            details.append("Wind: \(windSpeed)")
        }

        if preferences.includeFeelsLike, let feelsLike = weather.feelsLike {
            details.append("Feels like: \(feelsLike)")
        }

        if preferences.includeUVIndex, let uvIndex = weather.metrics?.uvIndex {
            details.append("UV: \(uvIndex)")
        }

        if preferences.includeRainChance {
            if let rainChance = weather.metrics?.rainChance ?? todayForecast?.chanceOfRain {
                details.append("Rain: \(rainChance)")
            }
        }

        if preferences.includeVisibility, let visibility = weather.metrics?.visibility {
            details.append("Visibility: \(visibility)")
        }

        return Array(details.prefix(limit))
    }

    private func alertBody(
        base: String,
        weather: WeatherInfo,
        preferences: NotificationContentPreference,
        limit: Int = 2
    ) -> String {
        let details = notificationSupplementaryDetails(for: weather, preferences: preferences, limit: limit)
        guard !details.isEmpty else { return base }
        return "\(base) • \(details.joined(separator: " • "))"
    }
    
    // MARK: - Severe Weather Alerts
    
    func checkSevereWeather(weather: WeatherInfo) {
        guard settings.severeWeatherEnabled else { return }
        guard authorizationStatus == .authorized else { return }
        let assessment = Self.severeWeatherAssessment(for: weather)
        guard assessment.isSevere else { return }

        // One alert per cooldown window while a condition persists — without
        // this every refresh during a storm re-alerted. Severe ignores quiet
        // hours (safety critical).
        if let last = alertState.state.lastSevereAlertDate,
           Date().timeIntervalSince(last) < Double(settings.severeWeatherAlertCooldownMinutes) * 60 {
            return
        }

        sendSevereWeatherAlert(weather: weather, assessment: assessment)
        alertState.update { $0.lastSevereAlertDate = Date() }
    }

    static func severeWeatherAssessment(for weather: WeatherInfo) -> SevereWeatherAssessment {
        let condition = weather.condition.lowercased()
        let severeConditions: [(keyword: String, detail: String, symbol: String)] = [
            ("thunderstorm", "Thunderstorm conditions are possible in \(weather.location.city).", "cloud.bolt.rain.fill"),
            ("strong storms", "Stormy conditions are building in \(weather.location.city).", "cloud.bolt.rain.fill"),
            ("tropical storm", "Tropical storm conditions are possible in \(weather.location.city).", "hurricane"),
            ("hail", "Hail is possible in \(weather.location.city).", "cloud.hail.fill"),
            ("squall", "Squally conditions are possible in \(weather.location.city).", "wind"),
            ("blizzard", "Blizzard conditions are possible in \(weather.location.city).", "wind.snow"),
            ("heavy snow", "Heavy snow is possible in \(weather.location.city).", "snowflake"),
            ("heavy rain", "Heavy rain is expected in \(weather.location.city).", "cloud.heavyrain.fill")
        ]

        if let match = severeConditions.first(where: { condition.contains($0.keyword) }) {
            return SevereWeatherAssessment(
                isSevere: true,
                headline: "Severe weather possible",
                detail: match.detail,
                symbol: match.symbol
            )
        }

        if let windSpeed = weather.metrics?.windSpeed,
           let windValue = parseWindSpeedValue(windSpeed),
           windValue >= 40 {
            return SevereWeatherAssessment(
                isSevere: true,
                headline: "Dangerous wind possible",
                detail: "Strong winds around \(windSpeed) are possible in \(weather.location.city).",
                symbol: "wind"
            )
        }

        return SevereWeatherAssessment(isSevere: false, headline: "", detail: "", symbol: "")
    }
    
    private func parseWindSpeed(_ windString: String) -> Double? {
        Self.parseWindSpeedValue(windString)
    }

    /// Parse display wind string and return speed in **mph** for severe-weather heuristics.
    private static func parseWindSpeedValue(_ windString: String) -> Double? {
        guard let metersPerSecond = parseWindSpeedMetersPerSecond(windString) else { return nil }
        return metersPerSecond * 2.23694
    }

    /// Parse display wind string ("12 m/s", "40 km/h", "25 mph", "20 Knots") to m/s.
    /// Shared with the wind Live Activity manager.
    static func parseWindSpeedMetersPerSecond(_ windString: String) -> Double? {
        let lowercased = windString.lowercased()
        let cleaned = lowercased
            .replacingOccurrences(of: "km/h", with: "")
            .replacingOccurrences(of: "m/s", with: "")
            .replacingOccurrences(of: "mph", with: "")
            .replacingOccurrences(of: "knots", with: "")
            .replacingOccurrences(of: "knot", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "[^0-9.-]", with: "", options: .regularExpression)

        guard let value = Double(cleaned) else { return nil }

        if lowercased.contains("km/h") {
            return value / 3.6
        }
        if lowercased.contains("mph") {
            return value / 2.23694
        }
        if lowercased.contains("knot") {
            return value / 1.94384
        }
        // Default: m/s (app default wind unit)
        return value
    }
    
    private func sendSevereWeatherAlert(weather: WeatherInfo, assessment: SevereWeatherAssessment) {
        let content = UNMutableNotificationContent()
        content.title = "Severe Weather Alert"
        content.body = alertBody(
            base: assessment.detail,
            weather: weather,
            preferences: settings.severeWeatherContent,
            limit: 3
        )
        content.sound = getSound(for: "severeWeather") ?? .default
        content.categoryIdentifier = "WEATHER_ALERT"
        content.userInfo = ["type": "severeWeather", "location": weather.location.city]
        
        let request = UNNotificationRequest(
            identifier: "severeWeather_\(UUID().uuidString)",
            content: content,
            trigger: nil // Immediate
        )
        
        notificationCenter.add(request)
    }
    
    // MARK: - Rain Alerts

    /// One rain alert fed by the best data available: the minute-level forecast
    /// when the provider serves one (WeatherKit always; Open-Meteo via its
    /// 15-minute precipitation block), otherwise the hourly probability series.
    func checkRain(weather: WeatherInfo) {
        guard settings.rainAlertsEnabled else { return }
        guard authorizationStatus == .authorized else { return }
        guard !isInQuietHours() else { return }
        guard !isRainAlertSnoozed() else { return }

        let now = Date()

        // Minute-level path.
        let minuteSteps = weather.metrics?.minuteForecast ?? []
        if !minuteSteps.isEmpty {
            let currentlyRaining = minuteSteps.last(where: { $0.time <= now })?.isPrecipitating ?? false
            let onset = minuteSteps.first(where: { $0.time >= now && $0.isPrecipitating })

            // Cancellation: was predicting rain, minute data now says dry.
            if alertState.state.previousRainPrediction, onset == nil, !currentlyRaining {
                sendRainCancellationAlert(weather: weather)
                alertState.update {
                    $0.previousRainPrediction = false
                    $0.lastRainAlertDate = nil
                }
                return
            }

            alertState.update { $0.previousRainPrediction = (onset != nil) || currentlyRaining }

            guard let onset, !currentlyRaining else { return }
            guard shouldSendRainAlert(location: weather.location.city) else { return }

            let minutesUntil = max(1, Int(ceil(onset.time.timeIntervalSince(now) / 60)))
            sendRainStartingAlert(minutesUntil: minutesUntil, weather: weather)
            alertState.update {
                $0.lastRainAlertDate = Date()
                $0.lastRainAlertLocation = weather.location.city
            }
            return
        }

        // Hourly floor: first upcoming hour within 3 that clears the chance threshold.
        let nextHours = (weather.allHourlyData ?? weather.hourlyForecast)
            .filter { hour in
                guard let date = hour.sourceDate else { return false }
                return date >= now
            }
            .prefix(3)

        guard let rainyHour = nextHours.first(where: { hour in
            (hour.precipitationChance ?? 0) >= Double(settings.rainChanceThreshold) / 100.0
        }) else { return }

        guard shouldSendRainAlert(location: weather.location.city) else { return }

        sendHourlyRainAlert(hour: rainyHour, weather: weather)
        alertState.update {
            $0.lastRainAlertDate = Date()
            $0.lastRainAlertLocation = weather.location.city
        }
    }

    private func shouldSendRainAlert(location: String) -> Bool {
        guard let lastAlert = alertState.state.lastRainAlertDate else { return true }
        let cooldownSeconds = TimeInterval(settings.rainAlertCooldownMinutes * 60)

        if alertState.state.lastRainAlertLocation == location {
            return Date().timeIntervalSince(lastAlert) >= cooldownSeconds
        }
        return Date().timeIntervalSince(lastAlert) >= 3600
    }

    private func sendRainStartingAlert(minutesUntil: Int, weather: WeatherInfo) {
        let content = UNMutableNotificationContent()
        content.title = "Rain Alert"

        if minutesUntil <= 10 {
            content.body = alertBody(
                base: "Rain starting in about \(minutesUntil) minutes in \(weather.location.city)",
                weather: weather,
                preferences: settings.alertContent
            )
        } else {
            content.body = alertBody(
                base: "Rain expected within the hour in \(weather.location.city)",
                weather: weather,
                preferences: settings.alertContent
            )
        }

        content.sound = getSound(for: "minuteRain") ?? .default
        content.categoryIdentifier = "RAIN_ALERT"
        content.userInfo = ["type": "minuteRain", "minutesUntil": minutesUntil]

        let request = UNNotificationRequest(
            identifier: "minuteRain_\(UUID().uuidString)",
            content: content,
            trigger: nil // Immediate
        )

        notificationCenter.add(request)
    }

    private func sendHourlyRainAlert(hour: HourlyForecast, weather: WeatherInfo) {
        let chancePercent = Int(round((hour.precipitationChance ?? 0) * 100))
        let content = UNMutableNotificationContent()
        content.title = "Rain Alert"
        content.body = alertBody(
            base: "Rain likely around \(hour.time) in \(weather.location.city) (\(chancePercent)% chance)",
            weather: weather,
            preferences: settings.alertContent
        )
        content.sound = getSound(for: "rainAlert") ?? .default
        content.categoryIdentifier = "RAIN_ALERT"
        content.userInfo = ["type": "rainAlert", "time": hour.time]

        let request = UNNotificationRequest(
            identifier: "rainAlert_\(UUID().uuidString)",
            content: content,
            trigger: nil // Immediate
        )

        notificationCenter.add(request)
    }

    private func sendRainCancellationAlert(weather: WeatherInfo) {
        let content = UNMutableNotificationContent()
        content.title = "Rain Alert Cancelled"
        content.body = alertBody(
            base: "Rain forecast cancelled for \(weather.location.city). Clear skies ahead.",
            weather: weather,
            preferences: settings.alertContent
        )
        content.sound = getSound(for: "rainCancelled") ?? .default
        content.categoryIdentifier = "RAIN_ALERT"
        content.userInfo = ["type": "rainCancelled"]

        let request = UNNotificationRequest(
            identifier: "rainCancelled_\(UUID().uuidString)",
            content: content,
            trigger: nil  // Immediate
        )

        notificationCenter.add(request)
    }
    
    // MARK: - UV Alerts

    func checkUVAlert(weather: WeatherInfo) {
        guard settings.uvAlertsEnabled else { return }
        guard authorizationStatus == .authorized else { return }
        guard !isInQuietHours() else { return }

        guard let uvIndex = weather.metrics?.uvIndex,
              uvIndex >= settings.uvThreshold else { return }

        // Check if we should send alert based on cooldown and location
        let state = alertState.state
        if let lastAlert = state.lastUVAlertDate {
            let elapsed = Date().timeIntervalSince(lastAlert)
            let cooldownSeconds = Double(settings.uvAlertCooldownMinutes) * 60

            // Same location check with cooldown (default 3 hours)
            if state.lastUVAlertLocation == weather.location.city {
                // Don't alert if within cooldown period
                guard elapsed >= cooldownSeconds else { return }

                // Don't alert if UV hasn't increased significantly (at least 2 points)
                if let lastIndex = state.lastUVAlertIndex {
                    guard uvIndex >= lastIndex + 2 else { return }
                }
            }
            // Different location - check if we alerted recently (within 1 hour) to avoid spam when traveling
            else if elapsed < 3600 {
                return
            }
        }

        // Send alert and track it
        sendUVAlert(weather: weather, uvIndex: uvIndex)
        alertState.update {
            $0.lastUVAlertDate = Date()
            $0.lastUVAlertLocation = weather.location.city
            $0.lastUVAlertIndex = uvIndex
        }
    }
    
    private func sendUVAlert(weather: WeatherInfo, uvIndex: Int) {
        let content = UNMutableNotificationContent()
        content.title = "High UV Index"
        content.body = alertBody(
            base: "UV Index \(uvIndex) in \(weather.location.city). Protect your skin.",
            weather: weather,
            preferences: settings.alertContent
        )
        content.sound = getSound(for: "uvAlert") ?? .default
        content.categoryIdentifier = "UV_ALERT"
        content.userInfo = ["type": "uvAlert", "uvIndex": uvIndex]
        
        let request = UNNotificationRequest(
            identifier: "uvAlert_\(UUID().uuidString)",
            content: content,
            trigger: nil // Immediate
        )
        
        notificationCenter.add(request)
    }
    
    // MARK: - Orchestrated Checks

    /// Every immediate alert check in one call — used by the ViewModel after
    /// automatic refreshes and by the background refresh task.
    func runAllAlertChecks(weather: WeatherInfo, temperatureUnit: TemperatureUnit) {
        checkSevereWeather(weather: weather)
        checkLightningAlert(weather: weather)
        checkRain(weather: weather)
        checkUVAlert(weather: weather)
        checkTemperatureChange(weather: weather, temperatureUnit: temperatureUnit)
        checkWindAlert(weather: weather)
        checkPrecipitationProbability(weather: weather)
    }

    // MARK: - Lightning Alerts

    /// Forecast-driven half: thunderstorms in the next hour mean lightning is
    /// possible — distinct from the generic severe alert (that reacts to the
    /// current condition; this watches the approaching hourly series). Runs
    /// wherever runAllAlertChecks runs, so the background refresh delivers it
    /// with the app closed. Ignores quiet hours (safety).
    func checkLightningAlert(weather: WeatherInfo) {
        guard settings.lightningAlertsEnabled else { return }
        guard authorizationStatus == .authorized else { return }

        let now = Date()
        let nextHour = (weather.allHourlyData ?? weather.hourlyForecast)
            .filter { hour in
                guard let date = hour.sourceDate else { return false }
                return date > now && date <= now.addingTimeInterval(3600)
            }

        let stormy = nextHour.contains { hour in
            let condition = (hour.condition ?? "").lowercased()
            return condition.contains("thunderstorm") || condition.contains("storms")
        }
        guard stormy else { return }

        if let last = alertState.state.lastLightningAlertDate,
           Date().timeIntervalSince(last) < 60 * 60 { return }

        let content = UNMutableNotificationContent()
        content.title = "Lightning Possible"
        content.body = alertBody(
            base: "Thunderstorms forecast within the hour in \(weather.location.city). Lightning could be nearby — plan indoors.",
            weather: weather,
            preferences: settings.alertContent
        )
        content.sound = .default
        content.categoryIdentifier = "WEATHER_ALERT"
        content.userInfo = ["type": "lightningForecast"]

        notificationCenter.add(UNNotificationRequest(
            identifier: "lightningForecast_\(UUID().uuidString)",
            content: content,
            trigger: nil
        ))
        alertState.update { $0.lastLightningAlertDate = Date() }
    }

    // MARK: - Update Settings
    
    func updateSettings(_ newSettings: NotificationSettings, weather: WeatherInfo?, temperatureUnit: TemperatureUnit) {
        settings = newSettings
        // Reschedule daily forecast if time changed
        if let weather = weather {
            scheduleDailyForecast(weather: weather, temperatureUnit: temperatureUnit)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        if response.actionIdentifier == "VIEW_ACTION" {
            // Handle view action - will be handled in app
            NotificationCenter.default.post(name: NSNotification.Name("OpenWeatherDetails"), object: nil, userInfo: userInfo)
        } else if response.actionIdentifier == "SNOOZE_RAIN_ACTION" {
            Task { @MainActor in
                NotificationManager.shared.snoozeRainAlerts()
            }
        }
        
        completionHandler()
    }
    
    // MARK: - Temperature Change Alerts
    
    func checkTemperatureChange(weather: WeatherInfo, temperatureUnit: TemperatureUnit) {
        guard settings.temperatureChangeAlertsEnabled else { return }
        guard authorizationStatus == .authorized else { return }
        guard !isInQuietHours() else { return }
        
        // Parse current temperature from the display string (e.g., "72°F" or "22°C"),
        // extracting the leading numeric value, then normalize to Celsius so unit
        // switches between fetches never produce a false alert.
        let numericString = weather.temperature
            .replacingOccurrences(of: "°", with: "")
            .filter { $0.isNumber || $0 == "." || $0 == "-" }
        guard let displayTemp = Double(numericString) else { return }
        let currentCelsius = temperatureUnit == .celsius ? displayTemp : (displayTemp - 32) * 5.0 / 9.0

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        defer {
            alertState.update {
                $0.lastTemperatureCelsius = currentCelsius
                $0.lastTemperatureDate = Date()
                $0.lastTemperatureCity = weather.location.city
            }
        }

        guard let lastCelsius = alertState.state.lastTemperatureCelsius,
              let lastDate = alertState.state.lastTemperatureDate else { return }

        // Only compare against a sample from a previous calendar day in the same city.
        let lastDay = calendar.startOfDay(for: lastDate)
        guard lastDay < today else { return }
        if let lastCity = alertState.state.lastTemperatureCity, lastCity != weather.location.city { return }

        let change = abs(currentCelsius - lastCelsius)

        if change >= Double(settings.temperatureChangeThreshold) {
            let isWarmer = currentCelsius > lastCelsius
            let changeInDisplayUnit = temperatureUnit == .celsius ? change : change * 9.0 / 5.0
            sendTemperatureChangeAlert(change: changeInDisplayUnit, isWarmer: isWarmer, temperatureUnit: temperatureUnit, weather: weather)
        }
    }
    
    private func sendTemperatureChangeAlert(change: Double, isWarmer: Bool, temperatureUnit: TemperatureUnit, weather: WeatherInfo) {
        let changeFormatted = Int(change)
        let unitSymbol = temperatureUnit == .celsius ? "C" : "F"
        let direction = isWarmer ? "warmer" : "cooler"
        
        let content = UNMutableNotificationContent()
        content.title = "Temperature Change Alert"
        content.body = alertBody(
            base: "It's \(changeFormatted)°\(unitSymbol) \(direction) than yesterday.",
            weather: weather,
            preferences: settings.alertContent
        )
        content.sound = getSound(for: "temperatureChange") ?? .default
        content.categoryIdentifier = "TEMPERATURE_CHANGE"
        content.userInfo = ["type": "temperatureChange"]
        
        let request = UNNotificationRequest(identifier: "temperatureChange_\(UUID().uuidString)", content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { _ in }
    }
    
    // MARK: - Wind Speed Alerts
    
    func checkWindAlert(weather: WeatherInfo) {
        guard settings.windAlertsEnabled else { return }
        guard authorizationStatus == .authorized else { return }
        guard !isInQuietHours() else { return }
        
        guard let windSpeed = weather.metrics?.windSpeed else { return }
        guard let speedMetersPerSecond = Self.parseWindSpeedMetersPerSecond(windSpeed) else { return }

        let windUnit = WindSpeedUnit(rawValue: UserDefaults.standard.string(forKey: "Breezy.windSpeedUnit") ?? WindSpeedUnit.metersPerSecond.rawValue) ?? .metersPerSecond
        let thresholdMetersPerSecond: Double = {
            let threshold = Double(settings.windSpeedThreshold)
            switch windUnit {
            case .metersPerSecond: return threshold
            case .kilometersPerHour: return threshold / 3.6
            case .milesPerHour: return threshold / 2.23694
            case .knots: return threshold / 1.94384
            }
        }()
        
        if speedMetersPerSecond >= thresholdMetersPerSecond {
            // One alert per cooldown window while the wind stays strong.
            if let last = alertState.state.lastWindAlertDate,
               Date().timeIntervalSince(last) < Double(settings.windAlertCooldownMinutes) * 60 {
                return
            }
            sendWindAlert(speed: windSpeed, weather: weather)
            alertState.update { $0.lastWindAlertDate = Date() }
        }
    }
    
    private func sendWindAlert(speed: String, weather: WeatherInfo) {
        let content = UNMutableNotificationContent()
        content.title = "High Wind Alert"
        content.body = alertBody(
            base: "Wind speeds reaching \(speed). Take precautions.",
            weather: weather,
            preferences: settings.alertContent
        )
        content.sound = getSound(for: "windAlert") ?? .default
        content.categoryIdentifier = "WIND_ALERT"
        content.userInfo = ["type": "windAlert"]
        
        let request = UNNotificationRequest(identifier: "windAlert_\(UUID().uuidString)", content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { _ in }
    }
    
    // MARK: - Precipitation Probability Alerts
    
    func checkPrecipitationProbability(weather: WeatherInfo) {
        guard settings.precipitationProbabilityAlertsEnabled else { return }
        guard authorizationStatus == .authorized else { return }
        guard !isInQuietHours() else { return }
        
        guard let todayForecast = weather.dailyForecast.first else { return }
        
        // Parse chanceOfRain string (e.g., "75%" -> 75)
        guard let chanceOfRainStr = todayForecast.chanceOfRain,
              let probability = Int(chanceOfRainStr.replacingOccurrences(of: "%", with: "")) else {
            return
        }
        
        if probability >= settings.precipitationProbabilityThreshold {
            if let lastAlertDate = alertState.state.lastPrecipProbabilityAlertDate,
               Calendar.current.isDateInToday(lastAlertDate) {
                return
            }

            sendPrecipitationProbabilityAlert(probability: probability, weather: weather)
            alertState.update { $0.lastPrecipProbabilityAlertDate = Date() }
        }
    }
    
    private func sendPrecipitationProbabilityAlert(probability: Int, weather: WeatherInfo) {
        let content = UNMutableNotificationContent()
        content.title = "High Rain Probability"
        content.body = alertBody(
            base: "\(probability)% chance of rain today. Consider bringing an umbrella.",
            weather: weather,
            preferences: settings.alertContent
        )
        content.sound = getSound(for: "precipitationProbability") ?? .default
        content.categoryIdentifier = "PRECIPITATION_PROBABILITY"
        content.userInfo = ["type": "precipitationProbability"]
        
        let request = UNNotificationRequest(identifier: "precipProbability_\(UUID().uuidString)", content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
