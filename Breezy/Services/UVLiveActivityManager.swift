//
//  UVLiveActivityManager.swift
//  Breezy
//
//  Sun-protection Live Activity. Starts when the current UV index reaches the
//  user's UV alert threshold, shows when it drops back below, and ends (with
//  hysteresis so a jittery value doesn't flicker the card) once it's safely
//  under or at sunset.
//

import Foundation
import ActivityKit

@MainActor
final class UVLiveActivityManager {
    static let shared = UVLiveActivityManager()

    /// UV must fall this far below the threshold before the activity ends.
    private let endHysteresis = 1

    private var activity: Activity<UVActivityAttributes>?

    private init() {}

    var isActive: Bool { activity != nil }

    /// Reconcile the Live Activity with the latest forecast. Called after every
    /// successful weather fetch.
    func update(with weather: WeatherInfo) {
        guard enabled else {
            end()
            return
        }

        guard let uvIndex = weather.metrics?.uvIndex else {
            end()
            return
        }

        let threshold = UserDefaults.standard.notificationSettings.uvThreshold

        // Below threshold (with hysteresis once shown) — nothing to protect from.
        let active = activity != nil
        guard uvIndex >= (active ? threshold - endHysteresis : threshold) else {
            end()
            return
        }

        reconcile(cityName: weather.location.city, uvIndex: uvIndex, weather: weather)
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
        UserDefaults.standard.object(forKey: "Breezy.uvLiveActivityEnabled") as? Bool ?? true
    }

    // MARK: - Reconciliation

    private func reconcile(cityName: String, uvIndex: Int, weather: WeatherInfo) {
        let categoryText = weather.metrics?.uvIndexCategory ?? UVIndexHelper.category(for: uvIndex)
        let dropsBelowText = Self.uvDropTime(in: weather, threshold: UserDefaults.standard.notificationSettings.uvThreshold)
        let staleDate = weather.dailyForecast.first?.sunsetDate ?? Date().addingTimeInterval(2 * 60 * 60)

        if let activity {
            let state = activity.content.state
            guard state.uvIndex != uvIndex else { return }

            let newState = UVActivityAttributes.ContentState(
                uvIndex: uvIndex,
                categoryText: categoryText,
                dropsBelowText: dropsBelowText
            )
            Task {
                await activity.update(.init(state: newState, staleDate: staleDate))
            }
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

            let attributes = UVActivityAttributes(cityName: cityName)
            let state = UVActivityAttributes.ContentState(
                uvIndex: uvIndex,
                categoryText: categoryText,
                dropsBelowText: dropsBelowText
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

    /// "until 4 PM" from the first upcoming hour whose UV index falls below the
    /// threshold; nil when the whole hourly series stays high (the card then
    /// simply shows the index without an end time).
    private static func uvDropTime(in weather: WeatherInfo, threshold: Int) -> String? {
        let now = Date()
        let hours = (weather.allHourlyData ?? weather.hourlyForecast)
            .compactMap { hour -> (date: Date, uv: Int)? in
                guard let date = hour.sourceDate, let uv = hour.uvIndex, date > now else { return nil }
                return (date, uv)
            }
            .sorted { $0.date < $1.date }

        guard let drop = hours.first(where: { $0.uv < threshold }) else { return nil }
        return "until \(drop.date.formatted(date: .omitted, time: .shortened))"
    }
}
