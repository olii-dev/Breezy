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
        guard settings.quietHoursEnabled else { return false }
        
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        
        let start = settings.quietHoursStart
        let end = settings.quietHoursEnd
        
        // Handle cases where quiet hours span midnight
        if start > end {
            // Spans midnight: e.g., 22:00 - 07:00 next day
            return currentHour >= start || currentHour < end
        } else {
            // Same day: e.g., 01:00 - 05:00
            return currentHour >= start && currentHour < end
        }
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
            actions: [viewAction, dismissAction],
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
    
    // MARK: - Daily Forecast Notification
    
    func scheduleDailyForecast(weather: WeatherInfo, temperatureUnit: TemperatureUnit) {
        guard settings.dailyForecastEnabled else {
            cancelDailyForecast()
            return
        }
        
        // Check weekday restriction
        if settings.onlyWeekdayForecast {
            let calendar = Calendar.current
            let today = Date()
            let weekday = calendar.component(.weekday, from: today)
            
            // 1 = Sunday, 7 = Saturday
            if weekday == 1 || weekday == 7 {
                print("📅 Skipping weekend daily forecast (weekdays-only enabled)")
                return
            }
        }
        
        guard authorizationStatus == .authorized else { return }
        
        // Cancel existing forecasts before scheduling new ones
        cancelDailyForecast()
        
        let calendar = Calendar.current
        let now = Date()
        
        // Schedule for each time in dailyForecastTimes
        for (index, time) in settings.dailyForecastTimes.enumerated() {
            var dateComponents = DateComponents()
            dateComponents.hour = time.hour
            dateComponents.minute = time.minute
            
            guard let scheduledTime = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: now) else { continue }
            
            let isForTomorrow = now > scheduledTime
            let targetForecastIndex = isForTomorrow ? 1 : 0
            let targetDateLabel = isForTomorrow ? "Tomorrow" : "Today"
            
            let content = UNMutableNotificationContent()
            content.title = "\(targetDateLabel)'s Weather"
            content.body = formatDailyForecastBody(weather: weather, temperatureUnit: temperatureUnit, dayIndex: targetForecastIndex)
            content.sound = getSound(for: "dailyForecast") ?? .default
            content.categoryIdentifier = "DAILY_FORECAST"
            content.userInfo = ["type": "dailyForecast"]
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
            let request = UNNotificationRequest(
                identifier: "dailyForecast_\(index)",
                content: content,
                trigger: trigger
            )
            
            notificationCenter.add(request) { error in
                if let error = error {
                    print("Error scheduling daily forecast at \(time.hour):\(time.minute): \(error)")
                }
            }
        }
    }
    
    func cancelDailyForecast() {
        let identifiers = settings.dailyForecastTimes.indices.map { "dailyForecast_\($0)" }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
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

        // Severe weather ignores quiet hours (safety critical)
        if assessment.isSevere {
            sendSevereWeatherAlert(weather: weather, assessment: assessment)
        }
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

    private static func parseWindSpeedValue(_ windString: String) -> Double? {
        // Parse wind speed from strings like "25 mph" or "40 km/h"
        let lowercased = windString.lowercased()
        let isKmh = lowercased.contains("km/h")
        let cleaned = lowercased
            .replacingOccurrences(of: "mph", with: "")
            .replacingOccurrences(of: "km/h", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "[^0-9.-]", with: "", options: .regularExpression)
        
        guard let value = Double(cleaned) else { return nil }
        
        // Convert km/h to mph for comparison (threshold is in mph)
        if isKmh {
            return value * 0.621371 // Convert km/h to mph
        }
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
        content.sound = getSound(for: "severeWeather") ?? .defaultCritical
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
    
    func checkRainAlert(weather: WeatherInfo) {
        guard settings.rainAlertsEnabled else { return }
        guard authorizationStatus == .authorized else { return }
        guard !isInQuietHours() else { return }
        
        // Check hourly forecast for rain in next few hours
        let nextHours = weather.hourlyForecast.prefix(3)
        for hour in nextHours {
            let condition = (hour.condition ?? "").lowercased()
            if condition.contains("rain") || condition.contains("drizzle") || condition.contains("shower") {
                sendRainAlert(hour: hour, weather: weather)
                return // Only send one alert
            }
        }
    }
    
    private func sendRainAlert(hour: HourlyForecast, weather: WeatherInfo) {
        let content = UNMutableNotificationContent()
        content.title = "Rain Alert"
        content.body = alertBody(
            base: "Rain expected at \(hour.time) in \(weather.location.city)",
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
    
    // MARK: - UV Alerts
    
    // UV Alert Tracking Structure
    private struct UVAlertInfo: Codable {
        let date: Date
        let location: String
        let uvIndex: Int
    }
    
    private var lastUVAlertInfo: UVAlertInfo? {
        get {
            if let data = UserDefaults.standard.data(forKey: "Breezy.lastUVAlert"),
               let info = try? JSONDecoder().decode(UVAlertInfo.self, from: data) {
                return info
            }
            return nil
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "Breezy.lastUVAlert")
            }
        }
    }
    
    func checkUVAlert(weather: WeatherInfo) {
        guard settings.uvAlertsEnabled else { return }
        guard authorizationStatus == .authorized else { return }
        guard !isInQuietHours() else { return }
        
        guard let uvIndex = weather.metrics?.uvIndex,
              uvIndex >= settings.uvThreshold else { return }
        
        // Check if we should send alert based on cooldown and location
        if let lastAlert = lastUVAlertInfo {
            let now = Date()
            let timeSinceLastAlert = now.timeIntervalSince(lastAlert.date)
            let cooldownSeconds = Double(settings.uvAlertCooldownMinutes) * 60
            
            // Same location check with cooldown (default 3 hours)
            if lastAlert.location == weather.location.city {
                // Don't alert if within cooldown period
                guard timeSinceLastAlert >= cooldownSeconds else { return }
                
                // Don't alert if UV hasn't increased significantly (at least 2 points)
                guard uvIndex >= lastAlert.uvIndex + 2 else { return }
            }
            // Different location - check if we alerted recently (within 1 hour) to avoid spam when traveling
            else if timeSinceLastAlert < 3600 {
                return
            }
        }
        
        // Send alert and track it
        sendUVAlert(weather: weather, uvIndex: uvIndex)
        lastUVAlertInfo = UVAlertInfo(
            date: Date(),
            location: weather.location.city,
            uvIndex: uvIndex
        )
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
    
    // MARK: - Minute Precipitation Alerts
    
    private var lastRainAlertTime: Date? {
        get { UserDefaults.standard.object(forKey: "Breezy.lastRainAlertTime") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "Breezy.lastRainAlertTime") }
    }
    
    private var lastRainAlertLocation: String? {
        get { UserDefaults.standard.string(forKey: "Breezy.lastRainAlertLocation") }
        set { UserDefaults.standard.set(newValue, forKey: "Breezy.lastRainAlertLocation") }
    }
    
    private var previousRainPrediction: Bool {
        get { UserDefaults.standard.bool(forKey: "Breezy.previousRainPrediction") }
        set { UserDefaults.standard.set(newValue, forKey: "Breezy.previousRainPrediction") }
    }
    
    func checkMinutePrecipitation(weather: WeatherInfo) {
        guard settings.minuteRainAlertsEnabled else { return }
        guard authorizationStatus == .authorized else { return }
        guard !isInQuietHours() else { return }
        
        // Check if we have minute forecast data
        // For now, we'll use hourly forecast as a proxy since WeatherKit minute forecast
        // requires separate API call. This checks next hour for rain.
        guard let nextHour = weather.hourlyForecast.first(where: { hour in
            let now = Calendar.current.component(.hour, from: Date())
            return hour.hourValue > now
        }) else { return }
        
        let condition = (nextHour.condition ?? "").lowercased()
        let willRain = condition.contains("rain") || condition.contains("drizzle") || condition.contains("shower")
        
        // Check for rain cancellation (was predicting rain, now not)
        if previousRainPrediction && !willRain {
            sendRainCancellationAlert(weather: weather)
            previousRainPrediction = false
            return
        }
        
        // Update tracking
        previousRainPrediction = willRain
        
        // If rain is expected, check cooldown before alerting
        if willRain {
            guard shouldSendRainAlert(location: weather.location.city) else { return }
            
            // Calculate approximate minutes until rain
            let now = Calendar.current.component(.hour, from: Date())
            let minutesUntil = (nextHour.hourValue - now) * 60
            
            sendMinuteRainAlert(minutesUntil: minutesUntil, weather: weather)
            lastRainAlertTime = Date()
            lastRainAlertLocation = weather.location.city
        }
    }
    
    private func shouldSendRainAlert(location: String) -> Bool {
        guard let lastAlert = lastRainAlertTime else { return true }
        let cooldownSeconds = TimeInterval(settings.rainAlertCooldownMinutes * 60)
        
        if lastRainAlertLocation == location {
            return Date().timeIntervalSince(lastAlert) >= cooldownSeconds
        }
        return Date().timeIntervalSince(lastAlert) >= 3600
    }
    
    private func sendMinuteRainAlert(minutesUntil: Int, weather: WeatherInfo) {
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
        
        // Reset cooldown timer since this is helpful info
        lastRainAlertTime = nil
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
        }
        
        completionHandler()
    }
    
    // MARK: - Temperature Change Alerts
    
    func checkTemperatureChange(weather: WeatherInfo, temperatureUnit: TemperatureUnit) {
        guard settings.temperatureChangeAlertsEnabled else { return }
        guard authorizationStatus == .authorized else { return }
        guard !isInQuietHours() else { return }
        
        let yesterdayTemp = UserDefaults.standard.double(forKey: "Breezy.lastTemperature")
        
        // Parse current temperature from string (e.g., "72" or "22.5")
        guard let currentTemp = Double(weather.temperature.replacingOccurrences(of: "°", with: "").trimmingCharacters(in: .whitespaces)) else {
            return
        }
        
        guard yesterdayTemp != 0 else {
            UserDefaults.standard.set(currentTemp, forKey: "Breezy.lastTemperature")
            return
        }
        
        let change = abs(currentTemp - yesterdayTemp)
        
        if change >= Double(settings.temperatureChangeThreshold) {
            let isWarmer = currentTemp > yesterdayTemp
            sendTemperatureChangeAlert(change: change, isWarmer: isWarmer, temperatureUnit: temperatureUnit, weather: weather)
        }
        
        UserDefaults.standard.set(currentTemp, forKey: "Breezy.lastTemperature")
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
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Error sending temperature change alert: \(error.localizedDescription)")
            } else {
                print("🌡️ Temperature change alert sent: \(changeFormatted)°\(unitSymbol) \(direction)")
            }
        }
    }
    
    // MARK: - Wind Speed Alerts
    
    func checkWindAlert(weather: WeatherInfo) {
        guard settings.windAlertsEnabled else { return }
        guard authorizationStatus == .authorized else { return }
        guard !isInQuietHours() else { return }
        
        guard let windSpeed = weather.metrics?.windSpeed else { return }
        
        let components = windSpeed.split(separator: " ")
        guard let speedString = components.first, let speedValue = Double(speedString) else { return }
        
        if speedValue >= Double(settings.windSpeedThreshold) {
            sendWindAlert(speed: windSpeed, weather: weather)
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
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Error sending wind alert: \(error.localizedDescription)")
            } else {
                print("💨 Wind alert sent: \(speed)")
            }
        }
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
            let lastAlertKey = "Breezy.lastPrecipProbabilityAlert"
            if let lastAlertDate = UserDefaults.standard.object(forKey: lastAlertKey) as? Date {
                let calendar = Calendar.current
                if calendar.isDateInToday(lastAlertDate) {
                    return
                }
            }
            
            sendPrecipitationProbabilityAlert(probability: probability, weather: weather)
            UserDefaults.standard.set(Date(), forKey: lastAlertKey)
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
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Error sending precipitation probability alert: \(error.localizedDescription)")
            } else {
                print("🌧️ Precipitation probability alert sent: \(probability)%")
            }
        }
    }
}
