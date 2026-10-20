//
//  AuroraLiveActivityManager.swift
//  Breezy
//
//  Lock Screen / Dynamic Island card while aurora conditions are plausible
//  tonight. Started when the aurora assessment clears the bar, ended when it
//  clearly doesn't (hysteresis band prevents flap around the threshold) or at
//  dawn — whichever comes first. Driven by AuroraAlertManager.
//

import Foundation
import ActivityKit

@MainActor
final class AuroraLiveActivityManager {
    static let shared = AuroraLiveActivityManager()

    private var activity: Activity<AuroraActivityAttributes>?

    private init() {}

    func restore() {
        guard activity == nil else { return }
        activity = Activity<AuroraActivityAttributes>.activities.first { $0.activityState == .active }
    }

    private func adoptExistingActivityIfNeeded() {
        guard activity == nil else { return }
        activity = Activity<AuroraActivityAttributes>.activities.first { $0.activityState == .active }
    }

    func update(snapshot: AuroraKit.Snapshot, weather: WeatherInfo) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        adoptExistingActivityIfNeeded()

        // Hysteresis: 0.5 to start, 0.3 to end — quiet skies and marginal
        // odds shouldn't pin the Lock Screen.
        if activity == nil {
            guard snapshot.isActive, snapshot.score >= 0.5 else { return }
            start(snapshot: snapshot, weather: weather)
        } else {
            guard snapshot.score < 0.3 || !snapshot.isNight else {
                refresh(snapshot: snapshot, weather: weather)
                return
            }
            end()
        }
    }

    func end() {
        activity = nil
        let strays = Activity<AuroraActivityAttributes>.activities.filter { $0.activityState == .active }
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

    // MARK: - Content

    private func dawnDate(weather: WeatherInfo) -> Date {
        let now = Date()
        // Tomorrow's sunrise if today's has passed; else today's.
        if let sunrise = weather.dailyForecast.first?.sunriseDate, sunrise > now {
            return sunrise
        }
        if weather.dailyForecast.count > 1, let sunrise = weather.dailyForecast[1].sunriseDate {
            return sunrise
        }
        // Polar/missing data: 8 hours out, capped at the next fetch.
        return now.addingTimeInterval(8 * 60 * 60)
    }

    private func makeState(snapshot: AuroraKit.Snapshot, weather: WeatherInfo) -> AuroraActivityAttributes.ContentState {
        AuroraActivityAttributes.ContentState(
            kp: snapshot.kp ?? 0,
            requiredKp: snapshot.requiredKp ?? AuroraKit.requiredKp(latitude: snapshot.latitude),
            bzNanoteslas: snapshot.bzNanoteslas,
            cloudPercent: snapshot.cloudFraction.map { Int(($0 * 100).rounded()) },
            moonPercent: snapshot.moonIllumination.map { Int(($0 * 100).rounded()) },
            dawnDate: dawnDate(weather: weather),
            verdict: snapshot.verdict
        )
    }

    private func start(snapshot: AuroraKit.Snapshot, weather: WeatherInfo) {
        let state = makeState(snapshot: snapshot, weather: weather)
        do {
            activity = try Activity.request(
                attributes: AuroraActivityAttributes(cityName: weather.location.city),
                content: .init(state: state, staleDate: min(state.dawnDate, Date().addingTimeInterval(3 * 60 * 60))),
                pushType: nil
            )
        } catch {
            activity = nil
        }
    }

    private func refresh(snapshot: AuroraKit.Snapshot, weather: WeatherInfo) {
        guard let activity else { return }
        let state = makeState(snapshot: snapshot, weather: weather)
        // Kp moves slowly; skip no-op updates to save budget.
        let current = activity.content.state
        guard abs(current.kp - state.kp) >= 0.5
                || current.verdict != state.verdict
                || current.dawnDate.timeIntervalSince(state.dawnDate) > 600 else { return }
        let staleDate = min(state.dawnDate, Date().addingTimeInterval(3 * 60 * 60))
        Task {
            await activity.update(.init(state: state, staleDate: staleDate))
        }
    }
}
