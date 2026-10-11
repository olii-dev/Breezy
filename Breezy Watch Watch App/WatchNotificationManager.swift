//
//  WatchNotificationManager.swift
//  Breezy Watch Watch App
//
//  Wrist-local weather alerts. The iPhone's notifications already mirror to
//  the watch whenever the phone is present, so these fire ONLY when the phone
//  is unreachable — complete wrist coverage with no double buzzes.
//

import Foundation
import UserNotifications
import WatchConnectivity

final class WatchNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = WatchNotificationManager()

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    // MARK: - Settings (app group, watch-local)

    enum Keys {
        static let rainEnabled = "WatchNotifications.RainEnabled"
        static let severeEnabled = "WatchNotifications.SevereEnabled"
        static let dailyEnabled = "WatchNotifications.DailyEnabled"
        static let phoneForecastHour = "WatchPhoneForecastHour"
        static let phoneForecastMinute = "WatchPhoneForecastMinute"
        static let state = "WatchNotifications.State.v1"
    }

    var rainEnabled: Bool {
        get { bool(Keys.rainEnabled, default: true) }
        set { setBool(newValue, Keys.rainEnabled) }
    }

    var severeEnabled: Bool {
        get { bool(Keys.severeEnabled, default: true) }
        set { setBool(newValue, Keys.severeEnabled) }
    }

    var dailyEnabled: Bool {
        get { bool(Keys.dailyEnabled, default: false) }
        set { setBool(newValue, Keys.dailyEnabled) }
    }

    private func bool(_ key: String, default defaultValue: Bool) -> Bool {
        guard let defaults = UserDefaults(suiteName: WatchAppStorageKey.appGroup) else { return defaultValue }
        return defaults.object(forKey: key) as? Bool ?? defaultValue
    }

    private func setBool(_ value: Bool, _ key: String) {
        UserDefaults(suiteName: WatchAppStorageKey.appGroup)?.set(value, forKey: key)
    }

    // MARK: - Cooldown state (leniently decoded)

    private struct AlertState: Codable {
        var lastRainAlert: Date?
        var lastSevereAlert: Date?

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            lastRainAlert = try c.decodeIfPresent(Date.self, forKey: .lastRainAlert)
            lastSevereAlert = try c.decodeIfPresent(Date.self, forKey: .lastSevereAlert)
        }
    }

    private var state: AlertState {
        get {
            guard let defaults = UserDefaults(suiteName: WatchAppStorageKey.appGroup),
                  let data = defaults.data(forKey: Keys.state),
                  let decoded = try? JSONDecoder().decode(AlertState.self, from: data) else {
                return AlertState()
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults(suiteName: WatchAppStorageKey.appGroup)?.set(data, forKey: Keys.state)
            }
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    // MARK: - Checks

    /// Runs after every watch weather refresh (background or foreground).
    /// When the iPhone is reachable it defers entirely — the phone's alerts
    /// mirror to the wrist — and clears anything pending from an earlier
    /// phone-less stretch.
    func runChecks(weather: WatchWeatherData, phoneReachable: Bool) {
        guard phoneReachable == false else {
            cancelPendingImmediateAlerts()
            return
        }

        if rainEnabled { checkRain(weather) }
        if severeEnabled { checkSevere(weather) }
    }

    private func checkRain(_ weather: WatchWeatherData) {
        let threshold = 0.4
        let now = Date()

        let upcoming = weather.hourlyForecast
            .filter { $0.date >= now }
            .prefix(3)

        guard let rainyHour = upcoming.first(where: { hour in
            guard let chance = hour.precipitationChance else { return false }
            return (Double(chance.replacingOccurrences(of: "%", with: "")) ?? 0) / 100 >= threshold
        }) else { return }

        // 30-minute cooldown between watch rain alerts.
        if let last = state.lastRainAlert, now.timeIntervalSince(last) < 30 * 60 { return }

        var state = state
        state.lastRainAlert = now
        self.state = state

        let content = UNMutableNotificationContent()
        content.title = "Rain Alert"
        if let chance = rainyHour.precipitationChance {
            content.body = "Rain likely around \(rainyHour.time) in \(weather.city) (\(chance) chance)"
        } else {
            content.body = "Rain likely around \(rainyHour.time) in \(weather.city)"
        }
        content.sound = .default

        center.add(UNNotificationRequest(
            identifier: "watch.rain.\(UUID().uuidString)",
            content: content,
            trigger: nil
        ))
    }

    private func checkSevere(_ weather: WatchWeatherData) {
        let severeKeywords = ["thunderstorm", "strong storms", "tropical storm", "hail", "squall", "blizzard", "heavy snow", "heavy rain"]
        let lowered = weather.condition.lowercased()
        guard severeKeywords.contains(where: lowered.contains) else { return }

        // 3-hour cooldown while a condition persists.
        let now = Date()
        if let last = state.lastSevereAlert, now.timeIntervalSince(last) < 3 * 60 * 60 { return }

        var state = state
        state.lastSevereAlert = now
        self.state = state

        let content = UNMutableNotificationContent()
        content.title = "Severe Weather Alert"
        content.body = "\(weather.condition) in \(weather.city). Take care."
        content.sound = .default

        center.add(UNNotificationRequest(
            identifier: "watch.severe.\(UUID().uuidString)",
            content: content,
            trigger: nil
        ))
    }

    private func cancelPendingImmediateAlerts() {
        center.getPendingNotificationRequests { requests in
            let ids = requests
                .map(\.identifier)
                .filter { $0.hasPrefix("watch.rain.") || $0.hasPrefix("watch.severe.") }
            guard !ids.isEmpty else { return }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // MARK: - Daily forecast (opt-in; phone mirrors its own when together)

    func refreshDailyForecastSchedule(weather: WatchWeatherData) {
        let identifiers = ["watch.daily"]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        guard dailyEnabled else { return }

        let defaults = UserDefaults(suiteName: WatchAppStorageKey.appGroup)
        let hour = defaults?.object(forKey: Keys.phoneForecastHour) as? Int ?? 8
        let minute = defaults?.object(forKey: Keys.phoneForecastMinute) as? Int ?? 0

        let content = UNMutableNotificationContent()
        content.title = "Today's Weather"
        if let today = weather.dailyForecast.first {
            content.body = "\(today.condition) • High \(today.highTemp) • Low \(today.lowTemp)" + (today.precipitationChance == "0%" ? "" : " • \(today.precipitationChance) rain")
        } else {
            content.body = "Tap for today's forecast."
        }
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        center.add(UNNotificationRequest(
            identifier: "watch.daily",
            content: content,
            trigger: trigger
        ))
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
