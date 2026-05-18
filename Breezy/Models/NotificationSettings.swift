//
//  NotificationSettings.swift
//  Breezy
//
//  Notification preferences model
//

import Foundation
import UserNotifications

enum SoundOption: String, Codable, CaseIterable {
    case `default` = "default"
    case critical = "critical"
    case bell = "bell"
    case chime = "chime"
    case ding = "ding"
    case none = "none"
    
    var displayName: String {
        switch self {
        case .default: return "Default"
        case .critical: return "Critical Alert"
        case .bell: return "Bell"
        case .chime: return "Chime"
        case .ding: return "Ding"
        case .none: return "None"
        }
    }
    
    var unSound: UNNotificationSound? {
        switch self {
        case .default: return .default
        case .critical: return .defaultCritical
        case .bell: return UNNotificationSound(named: UNNotificationSoundName("bell"))
        case .chime: return UNNotificationSound(named: UNNotificationSoundName("chime"))
        case .ding: return UNNotificationSound(named: UNNotificationSoundName("ding"))
        case .none: return nil
        }
    }
}

struct NotificationContentPreference: Codable {
    var includeCondition: Bool = true
    var includeTemperatureRange: Bool = true
    var includeHumidity: Bool = false
    var includeWindSpeed: Bool = false
    var includeFeelsLike: Bool = false
    var includeUVIndex: Bool = true
    var includeRainChance: Bool = true
    var includeVisibility: Bool = false
}

struct ForecastTime: Codable {
    let hour: Int
    let minute: Int
}

struct NotificationSettings: Codable {
    // Daily Forecast
    var dailyForecastEnabled: Bool
    var dailyForecastHour: Int // 0-23
    var dailyForecastMinute: Int // 0-59
    
    // Severe Weather
    var severeWeatherEnabled: Bool
    
    // Rain Alerts
    var rainAlertsEnabled: Bool
    var rainThreshold: Int // Percentage (0-100)
    
    // Minute Precipitation Alerts
    var minuteRainAlertsEnabled: Bool
    var rainAlertCooldownMinutes: Int // Minutes between alerts (default 10)
    
    // UV Alerts
    var uvAlertsEnabled: Bool
    var uvThreshold: Int // UV Index (0-11)
    var uvAlertCooldownMinutes: Int // Minutes between UV alerts (default 180 = 3 hours)
    
    // Temperature Change Alerts
    var temperatureChangeAlertsEnabled: Bool
    var temperatureChangeThreshold: Int // Degrees difference from yesterday (default 10)
    
    // Wind Alerts
    var windAlertsEnabled: Bool
    var windSpeedThreshold: Int // mph or km/h depending on unit (default 40)
    
    // Precipitation Probability
    var precipitationProbabilityAlertsEnabled: Bool
    var precipitationProbabilityThreshold: Int // Percentage (default 70)
    
    // Quiet Hours
    var quietHoursEnabled: Bool
    var quietHoursStart: Int // Hour 0-23
    var quietHoursEnd: Int // Hour 0-23
    
    // Notification Preferences
    var useCriticalAlertsForSevere: Bool // Use critical alert sound for severe weather
    var onlyWeekdayForecast: Bool // Only send daily forecast on weekdays (Mon-Fri)
    
    // MARK: - Sound Customization
    var dailyForecastSound: SoundOption = .default
    var severeWeatherSound: SoundOption = .critical
    var rainAlertSound: SoundOption = .default
    var uvAlertSound: SoundOption = .default
    var temperatureChangeSound: SoundOption = .default
    var windAlertSound: SoundOption = .default
    var precipitationProbabilitySound: SoundOption = .default
    
    // MARK: - Content Customization
    var dailyForecastContent: NotificationContentPreference = NotificationContentPreference()
    var severeWeatherContent: NotificationContentPreference = NotificationContentPreference(includeHumidity: true, includeWindSpeed: true, includeVisibility: true)
    var alertContent: NotificationContentPreference = NotificationContentPreference()
    
    // MARK: - Multiple Daily Forecast Times
    var dailyForecastTimes: [ForecastTime] = [ForecastTime(hour: 8, minute: 0)]
    
    // MARK: - Default Values
    struct Defaults {
        static let uvThreshold = 6
        static let uvAlertCooldownMinutes = 180 // 3 hours
        static let rainAlertCooldownMinutes = 10
        static let temperatureChangeThreshold = 10 // degrees (applies to both C and F)
        static let windSpeedThreshold = 40 // speed units (applies to both km/h and mph)
        static let precipitationProbabilityThreshold = 50 // percentage
    }
    
    // MARK: - Reset Method
    mutating func resetThresholdsToDefaults() {
        self.uvThreshold = Defaults.uvThreshold
        self.uvAlertCooldownMinutes = Defaults.uvAlertCooldownMinutes
        self.rainAlertCooldownMinutes = Defaults.rainAlertCooldownMinutes
        self.temperatureChangeThreshold = Defaults.temperatureChangeThreshold
        self.windSpeedThreshold = Defaults.windSpeedThreshold
        self.precipitationProbabilityThreshold = Defaults.precipitationProbabilityThreshold
    }
    
    static var `default`: NotificationSettings {
        NotificationSettings(
            dailyForecastEnabled: true,
            dailyForecastHour: 8,
            dailyForecastMinute: 0,
            severeWeatherEnabled: true,
            rainAlertsEnabled: true,
            rainThreshold: 50,
            minuteRainAlertsEnabled: true,
            rainAlertCooldownMinutes: 10,
            uvAlertsEnabled: true,
            uvThreshold: 7,
            uvAlertCooldownMinutes: 180,
            temperatureChangeAlertsEnabled: false,
            temperatureChangeThreshold: 10,
            windAlertsEnabled: false,
            windSpeedThreshold: 40,
            precipitationProbabilityAlertsEnabled: false,
            precipitationProbabilityThreshold: 70,
            quietHoursEnabled: false,
            quietHoursStart: 22,
            quietHoursEnd: 7,
            useCriticalAlertsForSevere: true,
            onlyWeekdayForecast: false,
            dailyForecastSound: .default,
            severeWeatherSound: .critical,
            rainAlertSound: .default,
            uvAlertSound: .default,
            temperatureChangeSound: .default,
            windAlertSound: .default,
            precipitationProbabilitySound: .default,
            dailyForecastTimes: [ForecastTime(hour: 8, minute: 0)]
        )
    }
}

// MARK: - UserDefaults Extension for NotificationSettings

extension UserDefaults {
    private enum Keys {
        static let notificationSettings = "Breezy.notificationSettings"
    }
    
    var notificationSettings: NotificationSettings {
        get {
            if let data = data(forKey: Keys.notificationSettings),
               let settings = try? JSONDecoder().decode(NotificationSettings.self, from: data) {
                return settings
            }
            return NotificationSettings.default
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                set(data, forKey: Keys.notificationSettings)
            }
        }
    }
}

