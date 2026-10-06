//
//  SevereWeatherLiveActivityManager.swift
//  Breezy
//
//  Severe-weather Live Activity. Starts when the severe-weather assessment
//  trips and stays on the Lock Screen until the forecast clears — two
//  consecutive clear fetches are required so a single good fetch doesn't
//  retract a warning — or a 12-hour cap expires.
//

import Foundation
import ActivityKit

@MainActor
final class SevereWeatherLiveActivityManager {
    static let shared = SevereWeatherLiveActivityManager()

    private let maximumDuration: TimeInterval = 12 * 60 * 60
    /// Clear fetches required after the assessment clears before ending.
    private let clearFetchesRequired = 2

    private var activity: Activity<SevereWeatherActivityAttributes>?
    private var consecutiveClearFetches = 0
    private var startedAt: Date?

    private init() {}

    var isActive: Bool { activity != nil }

    /// Reconcile the Live Activity with the latest forecast. Called after every
    /// successful weather fetch.
    func update(with weather: WeatherInfo) {
        guard enabled else {
            end()
            return
        }

        let assessment = NotificationManager.severeWeatherAssessment(for: weather)

        guard assessment.isSevere else {
            consecutiveClearFetches += 1
            if activity != nil, consecutiveClearFetches >= clearFetchesRequired {
                end()
            }
            return
        }

        consecutiveClearFetches = 0

        // Hard cap so a stale warning can't squat on the Lock Screen forever.
        if let start = startedAt, Date().timeIntervalSince(start) > maximumDuration {
            end()
            // Re-start the clock if conditions are still severe.
            startedAt = Date()
        }

        reconcile(cityName: weather.location.city, assessment: assessment)
    }

    func end() {
        consecutiveClearFetches = 0
        startedAt = nil
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
        UserDefaults.standard.object(forKey: "Breezy.severeLiveActivityEnabled") as? Bool ?? true
    }

    // MARK: - Reconciliation

    private func reconcile(cityName: String, assessment: SevereWeatherAssessment) {
        let staleDate = Date().addingTimeInterval(2 * 60 * 60)

        if let activity {
            let state = activity.content.state
            guard state.headline != assessment.headline || state.detail != assessment.detail else { return }

            let newState = SevereWeatherActivityAttributes.ContentState(
                headline: assessment.headline,
                detail: assessment.detail,
                symbolName: assessment.symbol
            )
            Task {
                await activity.update(.init(state: newState, staleDate: staleDate))
            }
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

            startedAt = Date()
            let attributes = SevereWeatherActivityAttributes(cityName: cityName)
            let state = SevereWeatherActivityAttributes.ContentState(
                headline: assessment.headline,
                detail: assessment.detail,
                symbolName: assessment.symbol
            )
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
