//
//  BackgroundRefreshScheduler.swift
//  Breezy
//
//  BGAppRefreshTask engine: schedules opportunistic background wakes so weather
//  alerts, Live Activities and widgets keep up to date while the app is closed.
//  The system decides when wakes actually happen (typically a few times a day
//  based on usage); we just aim them at the next interesting weather moment.
//

import Foundation
import BackgroundTasks
import UserNotifications
import WidgetKit
import os.log

@MainActor
enum BackgroundRefreshScheduler {
    static let taskIdentifier = "com.breezy.weather.refresh"

    /// Default cadence when nothing specific is coming up.
    private static let defaultInterval: TimeInterval = 2 * 60 * 60
    /// Never ask for a wake sooner than this — the system throttles anyway.
    private static let minimumInterval: TimeInterval = 20 * 60

#if DEBUG
    private static let logger = Logger(subsystem: "com.breezy.weather", category: "background-refresh")
#endif

    /// Must run before the app finishes launching (AppDelegate).
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let appRefreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(appRefreshTask)
        }
    }

    /// Call when the app backgrounds — aims the next wake at the soonest
    /// interesting weather moment (rain onset, UV crossing, forecast slot),
    /// or the default cadence otherwise.
    static func schedule() {
        #if !targetEnvironment(simulator)
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(secondsUntilNextWake())
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Most common: a previous request is still pending (fine), or the
            // system refused the schedule (also fine — opportunistic by design).
            #if DEBUG
            logger.debug("submit failed: \(String(describing: error), privacy: .public)")
            #endif
        }
        #endif
    }

    /// Seconds until the next wake target: soonest of the default interval and
    /// interesting upcoming moments, floored at the minimum.
    static func secondsUntilNextWake(now: Date = Date(), weather: WeatherInfo? = nil) -> TimeInterval {
        var candidates: [TimeInterval] = [defaultInterval]

        if let weather {
            // Rain onset within the next two hours — wake just before it starts.
            if let minuteOnset = weather.metrics?.minuteForecast?.first(where: { $0.time >= now && $0.isPrecipitating }),
               minuteOnset.time.timeIntervalSince(now) > minimumInterval {
                candidates.append(minuteOnset.time.timeIntervalSince(now) - 10 * 60)
            } else {
                let upcoming = (weather.allHourlyData ?? weather.hourlyForecast)
                    .compactMap { hour -> (date: Date, chance: Double)? in
                        guard let date = hour.sourceDate, date > now else { return nil }
                        return (date, hour.precipitationChance ?? 0)
                    }
                    .sorted { $0.date < $1.date }
                if let rainy = upcoming.first(where: { $0.chance >= 0.5 }), rainy.date.timeIntervalSince(now) > minimumInterval {
                    candidates.append(rainy.date.timeIntervalSince(now) - 10 * 60)
                }
            }

            // UV crossing the alert threshold.
            let threshold = UserDefaults.standard.notificationSettings.uvThreshold
            if let uvCrossing = (weather.allHourlyData ?? [])
                .compactMap({ hour -> (date: Date, uv: Int)? in
                    guard let date = hour.sourceDate, let uv = hour.uvIndex, date > now else { return nil }
                    return (date, uv)
                })
                .sorted(by: { $0.date < $1.date })
                .first(where: { $0.uv >= threshold }) {
                candidates.append(max(uvCrossing.date.timeIntervalSince(now), minimumInterval))
            }
        }

        // Next daily-forecast slot (daily summary Live Activity + freshness).
        let settings = UserDefaults.standard.notificationSettings
        let calendar = Calendar.current
        for dayOffset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) else { continue }
            for time in settings.dailyForecastTimes {
                var components = calendar.dateComponents([.year, .month, .day], from: day)
                components.hour = time.hour
                components.minute = time.minute
                if let slot = calendar.date(from: components), slot > now {
                    candidates.append(slot.timeIntervalSince(now) + 2 * 60)
                }
            }
        }

        return max(candidates.min() ?? defaultInterval, minimumInterval)
    }

    // MARK: - Task Handler

    private static func handle(_ task: BGAppRefreshTask) {
        // Schedule the follow-up wake first — the task may be killed at any time.
        schedule()

        let work = Task { @MainActor in
            defer { task.setTaskCompleted(success: true) }

            guard !BackgroundTaskManager.shared.shouldLimitBackgroundActivity() else { return }

            guard let weather = await fetchWeather() else { return }

            let notificationManager = NotificationManager.shared
            await notificationManager.checkAuthorizationStatus()

            // Live Activities follow the forecast regardless of notification
            // permission — gating them here starved background updates for
            // users who declined notifications.
            LiveActivityHub.updateAll(with: weather)
            AuroraAlertManager.shared.update(with: weather)
            WidgetCenter.shared.reloadAllTimelines()

            guard notificationManager.authorizationStatus == .authorized else { return }
            notificationManager.runAllAlertChecks(weather: weather, temperatureUnit: Self.temperatureUnit())

            #if DEBUG
            logger.debug("background refresh ran checks")
            #endif
        }

        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    /// Cached-location fetch — no GPS in the background (same pattern as the
    /// App Intents answers: 1h-fresh cache, else refresh for the cached or
    /// saved location).
    @MainActor
    private static func fetchWeather() async -> WeatherInfo? {
        let source = WeatherSourceStore.selectedSource
        let cached = WeatherCache.load(source: source)
        if let cached, Date().timeIntervalSince1970 - cached.timestamp < 3_600 {
            return cached
        }

        guard let location = cached?.location ?? lastKnownLocation() else { return cached }

        let formatting = WeatherFormattingContext(
            temperatureUnit: temperatureUnit(),
            windSpeedUnit: windSpeedUnit(),
            pressureUnit: .hectopascals,
            visibilityUnit: .kilometers,
            precipitationUnit: .millimeters
        )
        return try? await WeatherProviderManager.shared.fetchWeather(for: location, formatting: formatting).weather
    }

    private static func lastKnownLocation() -> LocationData? {
        guard let data = UserDefaults.standard.data(forKey: "Breezy.selectedLocation") else {
            return nil
        }
        return try? JSONDecoder().decode(LocationData.self, from: data)
    }

    private static func temperatureUnit() -> TemperatureUnit {
        TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: "Breezy.temperatureUnit") ?? "") ?? .celsius
    }

    private static func windSpeedUnit() -> WindSpeedUnit {
        WindSpeedUnit(rawValue: UserDefaults.standard.string(forKey: "Breezy.windSpeedUnit") ?? "") ?? .metersPerSecond
    }
}
