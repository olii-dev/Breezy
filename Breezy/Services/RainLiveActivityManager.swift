//
//  RainLiveActivityManager.swift
//  Breezy
//
//  Rain-countdown Live Activity. Started when the forecast shows rain arriving
//  at the current location within the next two hours, updated as the forecast
//  shifts, and ended when rain begins, clears, or moves out of range. The
//  countdown itself renders client-side from rainStart, so keeping it alive
//  costs no update budget — every fetch just reconciles state.
//

import Foundation
import ActivityKit

@MainActor
final class RainLiveActivityManager {
    static let shared = RainLiveActivityManager()

    /// Rain expected closer than this is "starting now" — the countdown adds
    /// nothing, so the activity ends instead.
    private let minimumLeadTime: TimeInterval = 10 * 60
    /// Don't hold an activity for rain that's hours away.
    private let maximumLeadTime: TimeInterval = 2 * 60 * 60
    private let chanceThreshold = 0.45

    private var activity: Activity<RainActivityAttributes>?

    private init() {}

    var isActive: Bool { activity != nil }

    /// Reconcile the Live Activity with the latest forecast. Called after every
    /// successful weather fetch.
    func update(with weather: WeatherInfo) {
        guard enabled else {
            end()
            return
        }

        let now = Date()

        if let onset = rainOnset(in: weather, now: now) {
            reconcile(cityName: weather.location.city, onset: onset, now: now)
        } else {
            end()
        }
    }

    func end() {
        guard let current = activity else { return }
        activity = nil
        Task {
            let final = current.content.state
            await current.end(
                .init(state: final, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
    }

    private var enabled: Bool {
        UserDefaults.standard.object(forKey: "Breezy.rainLiveActivityEnabled") as? Bool ?? true
    }

    // MARK: - Reconciliation

    private func reconcile(cityName: String, onset: RainOnset, now: Date) {
        let leadTime = onset.start.timeIntervalSince(now)

        // Rain already starting, or too far out to be worth the Lock Screen.
        if leadTime <= minimumLeadTime || leadTime > maximumLeadTime {
            end()
            return
        }

        let staleDate = (onset.end ?? onset.start).addingTimeInterval(45 * 60)

        if let activity {
            let state = activity.content.state
            let sameWindow = abs(state.rainStart.timeIntervalSince(onset.start)) < 120
                && state.chancePercent == Int((onset.chance * 100).rounded())
            guard !sameWindow else { return }

            let newState = RainActivityAttributes.ContentState(
                rainStart: onset.start,
                rainEnd: onset.end,
                chancePercent: Int((onset.chance * 100).rounded()),
                intensityText: onset.intensity
            )
            Task {
                await activity.update(.init(state: newState, staleDate: staleDate))
            }
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

            let attributes = RainActivityAttributes(cityName: cityName)
            let state = RainActivityAttributes.ContentState(
                rainStart: onset.start,
                rainEnd: onset.end,
                chancePercent: Int((onset.chance * 100).rounded()),
                intensityText: onset.intensity
            )
            do {
                activity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: staleDate),
                    pushType: nil
                )
            } catch {
                activity = nil
            }
        }
    }

    // MARK: - Onset detection

    private struct RainOnset {
        let start: Date
        let end: Date?
        let chance: Double
        let intensity: String?
    }

    /// First upcoming rain window: the minute forecast when the provider gives
    /// one, otherwise the hourly forecast. Nil when it's already raining or
    /// nothing is imminent.
    private func rainOnset(in weather: WeatherInfo, now: Date) -> RainOnset? {
        if let minuteOnset = minuteForecastOnset(in: weather, now: now) {
            return minuteOnset
        }
        return hourlyOnset(in: weather, now: now)
    }

    private func minuteForecastOnset(in weather: WeatherInfo, now: Date) -> RainOnset? {
        guard let minutes = weather.metrics?.minuteForecast, !minutes.isEmpty else { return nil }

        let currentlyRaining = minutes.first { $0.time >= now }.map { $0.isPrecipitating } ?? false
        guard !currentlyRaining else { return nil }

        guard let first = minutes.first(where: { $0.time >= now && $0.isPrecipitating }),
              first.time.timeIntervalSince(now) <= maximumLeadTime else { return nil }

        let end = minutes.first { $0.time > first.time && !$0.isPrecipitating }?.time
        let window = minutes.filter { $0.time >= first.time && $0.time <= (end ?? .distantFuture) }
        let chance = window.map(\.precipitationChance).max() ?? 0
        let intensity = window.map(\.precipitationIntensity).max()

        return RainOnset(
            start: first.time,
            end: end,
            chance: max(chance, 0.5),
            intensity: intensity.map { $0 > 2.5 ? "Heavy" : $0 > 0.5 ? "Moderate" : "Light" }
        )
    }

    private func hourlyOnset(in weather: WeatherInfo, now: Date) -> RainOnset? {
        let upcoming = weather.hourlyForecast
            .compactMap { hour -> (date: Date, hour: HourlyForecast)? in
                guard let date = hour.sourceDate, date >= now.addingTimeInterval(-600) else { return nil }
                return (date, hour)
            }
            .sorted { $0.date < $1.date }

        guard let first = upcoming.first else { return nil }

        // Already raining (or about to within the current hour): countdown
        // adds nothing.
        if first.date <= now.addingTimeInterval(minimumLeadTime), isRainy(first.hour) {
            return nil
        }

        guard let onset = upcoming.first(where: { $0.date <= now.addingTimeInterval(maximumLeadTime) && isRainy($0.hour) }) else {
            return nil
        }

        let end = upcoming.first { $0.date > onset.date && !isRainy($0.hour) }?.date
        return RainOnset(
            start: onset.date,
            end: end,
            chance: onset.hour.precipitationChance ?? 0.5,
            intensity: nil
        )
    }

    private func isRainy(_ hour: HourlyForecast) -> Bool {
        let condition = (hour.condition ?? "").lowercased()
        let conditionRainy = condition.contains("rain") || condition.contains("drizzle") || condition.contains("shower") || condition.contains("thunder")
        return conditionRainy && (hour.precipitationChance ?? 0) >= chanceThreshold
    }
}
