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
    case none = "none"

    var displayName: String {
        switch self {
        case .default: return "Default"
        case .none: return "None"
        }
    }

    var unSound: UNNotificationSound? {
        switch self {
        case .default: return .default
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
    var dailyForecastHour: Int // 0-23 (legacy; superseded by dailyForecastTimes)
    var dailyForecastMinute: Int // 0-59 (legacy; superseded by dailyForecastTimes)

    // Severe Weather
    var severeWeatherEnabled: Bool

    // Lightning (forecast-driven + live proximity when the feed is up)
    var lightningAlertsEnabled: Bool

    // Rain Alerts (hourly heads-up + short-fuse minute checks)
    var rainAlertsEnabled: Bool
    var rainChanceThreshold: Int // Percentage 0-100 for the hourly fallback path (default 40)
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
    var windAlertCooldownMinutes: Int // Minutes between wind alerts (default 60)

    // Severe Weather cooldown
    var severeWeatherAlertCooldownMinutes: Int // Minutes between severe alerts (default 180)

    // Precipitation Probability
    var precipitationProbabilityAlertsEnabled: Bool
    var precipitationProbabilityThreshold: Int // Percentage (default 70)

    // Quiet Hours
    var quietHoursEnabled: Bool
    var quietHoursStart: Int // Hour 0-23
    var quietHoursEnd: Int // Hour 0-23

    var onlyWeekdayForecast: Bool // Only send daily forecast on weekdays (Mon-Fri)

    // MARK: - Sound Customization
    var dailyForecastSound: SoundOption = .default
    var severeWeatherSound: SoundOption = .default
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

    // MARK: - Quiet Hours Check

    /// Hour-granular quiet-hours test for a given instant; spans midnight correctly.
    func isQuietHours(at date: Date = Date()) -> Bool {
        guard quietHoursEnabled else { return false }
        let hour = Calendar.current.component(.hour, from: date)
        if quietHoursStart > quietHoursEnd {
            return hour >= quietHoursStart || hour < quietHoursEnd
        }
        return hour >= quietHoursStart && hour < quietHoursEnd
    }

    // MARK: - Default Values
    struct Defaults {
        static let uvThreshold = 6
        static let uvAlertCooldownMinutes = 180 // 3 hours
        static let rainChanceThreshold = 40 // percentage
        static let rainAlertCooldownMinutes = 10
        static let temperatureChangeThreshold = 10 // degrees (applies to both C and F)
        static let windSpeedThreshold = 40 // speed units (applies to both km/h and mph)
        static let windAlertCooldownMinutes = 60
        static let severeWeatherAlertCooldownMinutes = 180
        static let precipitationProbabilityThreshold = 50 // percentage
    }

    // MARK: - Reset Method
    mutating func resetThresholdsToDefaults() {
        self.uvThreshold = Defaults.uvThreshold
        self.uvAlertCooldownMinutes = Defaults.uvAlertCooldownMinutes
        self.rainChanceThreshold = Defaults.rainChanceThreshold
        self.rainAlertCooldownMinutes = Defaults.rainAlertCooldownMinutes
        self.temperatureChangeThreshold = Defaults.temperatureChangeThreshold
        self.windSpeedThreshold = Defaults.windSpeedThreshold
        self.windAlertCooldownMinutes = Defaults.windAlertCooldownMinutes
        self.severeWeatherAlertCooldownMinutes = Defaults.severeWeatherAlertCooldownMinutes
        self.precipitationProbabilityThreshold = Defaults.precipitationProbabilityThreshold
    }

    static var `default`: NotificationSettings {
        NotificationSettings(
            dailyForecastEnabled: true,
            dailyForecastHour: 8,
            dailyForecastMinute: 0,
            severeWeatherEnabled: true,
            lightningAlertsEnabled: true,
            rainAlertsEnabled: true,
            rainChanceThreshold: Defaults.rainChanceThreshold,
            rainAlertCooldownMinutes: 10,
            uvAlertsEnabled: true,
            uvThreshold: 7,
            uvAlertCooldownMinutes: 180,
            temperatureChangeAlertsEnabled: false,
            temperatureChangeThreshold: 10,
            windAlertsEnabled: false,
            windSpeedThreshold: 40,
            windAlertCooldownMinutes: Defaults.windAlertCooldownMinutes,
            severeWeatherAlertCooldownMinutes: Defaults.severeWeatherAlertCooldownMinutes,
            precipitationProbabilityAlertsEnabled: false,
            precipitationProbabilityThreshold: 70,
            quietHoursEnabled: false,
            quietHoursStart: 22,
            quietHoursEnd: 7,
            onlyWeekdayForecast: false,
            dailyForecastTimes: [ForecastTime(hour: 8, minute: 0)]
        )
    }
}

// MARK: - Lenient Decoding
//
// Custom decoders use decodeIfPresent everywhere and fall back to the shipped
// defaults, so adding or renaming a field can never make decode fail (which
// previously reset every user's settings to defaults) and dropping a field
// simply ignores the stale JSON key.

extension NotificationContentPreference {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NotificationContentPreference()
        self.init()
        includeCondition = try c.decodeIfPresent(Bool.self, forKey: .includeCondition) ?? d.includeCondition
        includeTemperatureRange = try c.decodeIfPresent(Bool.self, forKey: .includeTemperatureRange) ?? d.includeTemperatureRange
        includeHumidity = try c.decodeIfPresent(Bool.self, forKey: .includeHumidity) ?? d.includeHumidity
        includeWindSpeed = try c.decodeIfPresent(Bool.self, forKey: .includeWindSpeed) ?? d.includeWindSpeed
        includeFeelsLike = try c.decodeIfPresent(Bool.self, forKey: .includeFeelsLike) ?? d.includeFeelsLike
        includeUVIndex = try c.decodeIfPresent(Bool.self, forKey: .includeUVIndex) ?? d.includeUVIndex
        includeRainChance = try c.decodeIfPresent(Bool.self, forKey: .includeRainChance) ?? d.includeRainChance
        includeVisibility = try c.decodeIfPresent(Bool.self, forKey: .includeVisibility) ?? d.includeVisibility
    }
}

extension ForecastTime {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hour = try c.decodeIfPresent(Int.self, forKey: .hour) ?? 8
        minute = try c.decodeIfPresent(Int.self, forKey: .minute) ?? 0
    }
}

extension NotificationSettings {
    private enum CodingKeys: String, CodingKey {
        case dailyForecastEnabled, dailyForecastHour, dailyForecastMinute
        case severeWeatherEnabled, severeWeatherAlertCooldownMinutes, lightningAlertsEnabled
        case rainAlertsEnabled, rainChanceThreshold, rainAlertCooldownMinutes
        case uvAlertsEnabled, uvThreshold, uvAlertCooldownMinutes
        case temperatureChangeAlertsEnabled, temperatureChangeThreshold
        case windAlertsEnabled, windSpeedThreshold, windAlertCooldownMinutes
        case precipitationProbabilityAlertsEnabled, precipitationProbabilityThreshold
        case quietHoursEnabled, quietHoursStart, quietHoursEnd
        case onlyWeekdayForecast
        case dailyForecastSound, severeWeatherSound, rainAlertSound, uvAlertSound
        case temperatureChangeSound, windAlertSound, precipitationProbabilitySound
        case dailyForecastContent, severeWeatherContent, alertContent
        case dailyForecastTimes
    }

    private static func decodeSound(_ raw: String?) -> SoundOption {
        // Legacy values (critical/bell/chime/ding) had no bundled sound assets — map to default.
        guard let raw, let option = SoundOption(rawValue: raw) else { return .default }
        return option
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NotificationSettings.default

        dailyForecastEnabled = try c.decodeIfPresent(Bool.self, forKey: .dailyForecastEnabled) ?? d.dailyForecastEnabled
        dailyForecastHour = try c.decodeIfPresent(Int.self, forKey: .dailyForecastHour) ?? d.dailyForecastHour
        dailyForecastMinute = try c.decodeIfPresent(Int.self, forKey: .dailyForecastMinute) ?? d.dailyForecastMinute
        severeWeatherEnabled = try c.decodeIfPresent(Bool.self, forKey: .severeWeatherEnabled) ?? d.severeWeatherEnabled
        lightningAlertsEnabled = try c.decodeIfPresent(Bool.self, forKey: .lightningAlertsEnabled) ?? d.lightningAlertsEnabled
        rainAlertsEnabled = try c.decodeIfPresent(Bool.self, forKey: .rainAlertsEnabled) ?? d.rainAlertsEnabled
        rainChanceThreshold = try c.decodeIfPresent(Int.self, forKey: .rainChanceThreshold) ?? d.rainChanceThreshold
        rainAlertCooldownMinutes = try c.decodeIfPresent(Int.self, forKey: .rainAlertCooldownMinutes) ?? d.rainAlertCooldownMinutes
        uvAlertsEnabled = try c.decodeIfPresent(Bool.self, forKey: .uvAlertsEnabled) ?? d.uvAlertsEnabled
        uvThreshold = try c.decodeIfPresent(Int.self, forKey: .uvThreshold) ?? d.uvThreshold
        uvAlertCooldownMinutes = try c.decodeIfPresent(Int.self, forKey: .uvAlertCooldownMinutes) ?? d.uvAlertCooldownMinutes
        temperatureChangeAlertsEnabled = try c.decodeIfPresent(Bool.self, forKey: .temperatureChangeAlertsEnabled) ?? d.temperatureChangeAlertsEnabled
        temperatureChangeThreshold = try c.decodeIfPresent(Int.self, forKey: .temperatureChangeThreshold) ?? d.temperatureChangeThreshold
        windAlertsEnabled = try c.decodeIfPresent(Bool.self, forKey: .windAlertsEnabled) ?? d.windAlertsEnabled
        windSpeedThreshold = try c.decodeIfPresent(Int.self, forKey: .windSpeedThreshold) ?? d.windSpeedThreshold
        windAlertCooldownMinutes = try c.decodeIfPresent(Int.self, forKey: .windAlertCooldownMinutes) ?? d.windAlertCooldownMinutes
        severeWeatherAlertCooldownMinutes = try c.decodeIfPresent(Int.self, forKey: .severeWeatherAlertCooldownMinutes) ?? d.severeWeatherAlertCooldownMinutes
        precipitationProbabilityAlertsEnabled = try c.decodeIfPresent(Bool.self, forKey: .precipitationProbabilityAlertsEnabled) ?? d.precipitationProbabilityAlertsEnabled
        precipitationProbabilityThreshold = try c.decodeIfPresent(Int.self, forKey: .precipitationProbabilityThreshold) ?? d.precipitationProbabilityThreshold
        quietHoursEnabled = try c.decodeIfPresent(Bool.self, forKey: .quietHoursEnabled) ?? d.quietHoursEnabled
        quietHoursStart = try c.decodeIfPresent(Int.self, forKey: .quietHoursStart) ?? d.quietHoursStart
        quietHoursEnd = try c.decodeIfPresent(Int.self, forKey: .quietHoursEnd) ?? d.quietHoursEnd
        onlyWeekdayForecast = try c.decodeIfPresent(Bool.self, forKey: .onlyWeekdayForecast) ?? d.onlyWeekdayForecast

        dailyForecastSound = Self.decodeSound(try c.decodeIfPresent(String.self, forKey: .dailyForecastSound))
        severeWeatherSound = Self.decodeSound(try c.decodeIfPresent(String.self, forKey: .severeWeatherSound))
        rainAlertSound = Self.decodeSound(try c.decodeIfPresent(String.self, forKey: .rainAlertSound))
        uvAlertSound = Self.decodeSound(try c.decodeIfPresent(String.self, forKey: .uvAlertSound))
        temperatureChangeSound = Self.decodeSound(try c.decodeIfPresent(String.self, forKey: .temperatureChangeSound))
        windAlertSound = Self.decodeSound(try c.decodeIfPresent(String.self, forKey: .windAlertSound))
        precipitationProbabilitySound = Self.decodeSound(try c.decodeIfPresent(String.self, forKey: .precipitationProbabilitySound))

        dailyForecastContent = try c.decodeIfPresent(NotificationContentPreference.self, forKey: .dailyForecastContent) ?? d.dailyForecastContent
        severeWeatherContent = try c.decodeIfPresent(NotificationContentPreference.self, forKey: .severeWeatherContent) ?? d.severeWeatherContent
        alertContent = try c.decodeIfPresent(NotificationContentPreference.self, forKey: .alertContent) ?? d.alertContent

        // Pre-multiple-times settings only carried the hour/minute pair; honor it
        // for the first slot instead of snapping those users to the 8:00 default.
        if c.contains(.dailyForecastTimes) {
            dailyForecastTimes = try c.decodeIfPresent([ForecastTime].self, forKey: .dailyForecastTimes) ?? d.dailyForecastTimes
        } else {
            let legacyHour = try c.decodeIfPresent(Int.self, forKey: .dailyForecastHour) ?? d.dailyForecastHour
            let legacyMinute = try c.decodeIfPresent(Int.self, forKey: .dailyForecastMinute) ?? d.dailyForecastMinute
            if legacyHour != d.dailyForecastHour || legacyMinute != d.dailyForecastMinute {
                dailyForecastTimes = [ForecastTime(hour: legacyHour, minute: legacyMinute)]
            } else {
                dailyForecastTimes = d.dailyForecastTimes
            }
        }
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
