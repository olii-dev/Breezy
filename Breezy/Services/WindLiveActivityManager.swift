//
//  WindLiveActivityManager.swift
//  Breezy
//
//  High-wind Live Activity. Starts when the current wind speed reaches the
//  user's wind alert threshold (same threshold as wind notifications) and
//  ends once it eases below 80% of the threshold or a 6-hour cap expires.
//

import Foundation
import ActivityKit

@MainActor
final class WindLiveActivityManager {
    static let shared = WindLiveActivityManager()

    private let maximumDuration: TimeInterval = 6 * 60 * 60
    /// Wind must ease to this fraction of the threshold before the activity ends.
    private let endFraction = 0.8

    private var activity: Activity<WindActivityAttributes>?
    private var startedAt: Date?

    private init() {}

    var isActive: Bool { activity != nil }

    /// Re-adopt a still-running activity after a process restart so updates
    /// and end() work again (activities are system-owned and outlive the app).
    func restore() {
        guard activity == nil else { return }
        activity = Activity<WindActivityAttributes>.activities.first { $0.activityState == .active }
    }

    /// Self-heal for when the launch restore missed one: without this, the
    /// ease-off floor misjudges and reconcile would stack a duplicate card.
    private func adoptExistingActivityIfNeeded() {
        guard activity == nil else { return }
        activity = Activity<WindActivityAttributes>.activities.first { $0.activityState == .active }
    }

    /// Reconcile the Live Activity with the latest forecast. Called after every
    /// successful weather fetch.
    func update(with weather: WeatherInfo) {
        guard enabled else {
            end()
            return
        }

        adoptExistingActivityIfNeeded()

        guard let windSpeedText = weather.metrics?.windSpeed,
              let speedMetersPerSecond = NotificationManager.parseWindSpeedMetersPerSecond(windSpeedText) else {
            end()
            return
        }

        let settings = UserDefaults.standard.notificationSettings
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

        let active = activity != nil
        let floor = active ? thresholdMetersPerSecond * endFraction : thresholdMetersPerSecond
        guard speedMetersPerSecond >= floor else {
            end()
            return
        }

        // Hard cap so a windy day doesn't pin the card all evening.
        if let start = startedAt, Date().timeIntervalSince(start) > maximumDuration {
            end()
            startedAt = Date()
        }

        reconcile(cityName: weather.location.city, weather: weather, windSpeedText: windSpeedText)
    }

    func end() {
        startedAt = nil
        activity = nil
        // Sweep every active activity of this type — a held-reference-only end
        // would leave strays behind if restore ever missed one.
        let strays = Activity<WindActivityAttributes>.activities.filter { $0.activityState == .active }
        guard !strays.isEmpty else { return }
        Task {
            for current in strays {
                let final = current.content.state
                await current.end(
                    .init(state: final, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
        }
    }

    private var enabled: Bool {
        UserDefaults.standard.object(forKey: "Breezy.windLiveActivityEnabled") as? Bool ?? true
    }

    // MARK: - Reconciliation

    private func reconcile(cityName: String, weather: WeatherInfo, windSpeedText: String) {
        let state = WindActivityAttributes.ContentState(
            speedText: windSpeedText,
            gustText: weather.metrics?.windGust.map { "gusting \($0)" },
            directionText: weather.metrics?.windDirectionCardinal.map { "from the \($0)" }
        )
        let staleDate = Date().addingTimeInterval(90 * 60)

        if let activity {
            let current = activity.content.state
            guard current.speedText != state.speedText || current.gustText != state.gustText else { return }
            Task {
                await activity.update(.init(state: state, staleDate: staleDate))
            }
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

            startedAt = Date()
            let attributes = WindActivityAttributes(cityName: cityName)
            do {
                activity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: staleDate),
                    pushType: nil
                )
            } catch {
                activity = nil
                startedAt = nil
            }
        }
    }
}
