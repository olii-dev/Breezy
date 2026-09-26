//
//  BreezyIntents.swift
//  Breezy
//
//  Siri / Shortcuts / Spotlight intents. Answer quick weather questions from
//  the cached forecast, refreshing from the active provider when the cache is
//  stale — so "will it rain tonight?" works without the app coming to the
//  foreground.
//

import AppIntents
import Foundation

// MARK: - Will It Rain?

struct RainCheckIntent: AppIntent {
    static var title: LocalizedStringResource = "Will It Rain?"
    static var description = IntentDescription("Checks whether rain is expected soon at your current Breezy location.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let answer = await BreezyIntentAnswers.rainCheck() else {
            return .result(dialog: "Open Breezy once so it can load your weather, then try again.")
        }
        return .result(dialog: IntentDialog(stringLiteral: answer))
    }
}

// MARK: - Current Weather

struct CurrentWeatherIntent: AppIntent {
    static var title: LocalizedStringResource = "Current Weather"
    static var description = IntentDescription("Reads the current conditions from Breezy at your saved location.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let answer = await BreezyIntentAnswers.currentWeather() else {
            return .result(dialog: "Open Breezy once so it can load your weather, then try again.")
        }
        return .result(dialog: IntentDialog(stringLiteral: answer))
    }
}

// MARK: - Shortcuts

struct BreezyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RainCheckIntent(),
            phrases: [
                "Will it rain in \(.applicationName)",
                "Will it rain tonight in \(.applicationName)"
            ],
            shortTitle: "Will It Rain?",
            systemImageName: "cloud.rain.fill"
        )
        AppShortcut(
            intent: CurrentWeatherIntent(),
            phrases: [
                "What's the weather in \(.applicationName)",
                "Current weather in \(.applicationName)"
            ],
            shortTitle: "Current Weather",
            systemImageName: "sun.max.fill"
        )
    }
}

// MARK: - Answer building

enum BreezyIntentAnswers {

    /// Cached forecast, refreshed through the provider when older than an hour.
    @MainActor
    private static func loadWeather() async -> WeatherInfo? {
        let source = WeatherSourceStore.selectedSource
        let cached = WeatherCache.load(source: source)
        if let cached, Date().timeIntervalSince1970 - cached.timestamp < 3_600 {
            return cached
        }

        // Prefer the cached location so a background intent doesn't need GPS.
        guard let location = cached?.location ?? lastKnownLocation() else { return cached }

        let formatting = WeatherFormattingContext(
            temperatureUnit: .celsius,
            windSpeedUnit: .metersPerSecond,
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

    @MainActor
    static func rainCheck() async -> String? {
        guard let weather = await loadWeather() else { return nil }

        let now = Date()
        let horizon = now.addingTimeInterval(12 * 3_600)

        // Minute-level precision first (WeatherKit), then hourly.
        if let minutes = weather.metrics?.minuteForecast {
            if let first = minutes.first(where: { $0.time >= now && $0.isPrecipitating }),
               first.time <= horizon {
                let minutesAway = max(1, Int(first.time.timeIntervalSince(now) / 60))
                return "Yes — rain starting in about \(minutesAway) minutes in \(weather.location.city)."
            }
        }

        let upcoming = weather.hourlyForecast
            .compactMap { hour -> (date: Date, hour: HourlyForecast)? in
                guard let date = hour.sourceDate, date >= now.addingTimeInterval(-600), date <= horizon else { return nil }
                return (date, hour)
            }
            .sorted { $0.date < $1.date }

        let rainy = upcoming.filter { entry in
            let condition = (entry.hour.condition ?? "").lowercased()
            let conditionRainy = condition.contains("rain") || condition.contains("drizzle") || condition.contains("shower") || condition.contains("thunder")
            return conditionRainy || (entry.hour.precipitationChance ?? 0) >= 0.4
        }

        if let first = rainy.first {
            let percent = Int((first.hour.precipitationChance ?? 0.5) * 100)
            let time = first.date.formatted(date: .omitted, time: .shortened)
            if first.date.timeIntervalSince(now) < 3_600 {
                return "Yes — rain likely around \(time) in \(weather.location.city) (\(percent)% chance)."
            }
            return "Rain expected around \(time) in \(weather.location.city) (\(percent)% chance)."
        }

        return "No rain expected in \(weather.location.city) for the next 12 hours."
    }

    @MainActor
    static func currentWeather() async -> String? {
        guard let weather = await loadWeather() else { return nil }
        return "It's \(weather.temperature) and \(weather.condition.lowercased()) in \(weather.location.city)."
    }
}
