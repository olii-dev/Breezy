//
//  DailySummaryLiveActivityManager.swift
//  Breezy
//
//  Time-boxed daily-forecast Live Activity. Starts only within a short window
//  after one of the user's daily-forecast times fires (morning app open or a
//  background refresh), and deliberately ends itself right away with a delayed
//  dismissal policy — ActivityKit keeps the final card on the Lock Screen
//  until then, so it self-removes after ~90 minutes without any follow-up.
//

import Foundation
import ActivityKit

@MainActor
final class DailySummaryLiveActivityManager {
    static let shared = DailySummaryLiveActivityManager()

    /// How long after a forecast slot the start window stays open.
    static let startWindow: TimeInterval = 20 * 60
    /// How long the card lingers on the Lock Screen before self-dismissing.
    private let dismissalDelay: TimeInterval = 90 * 60

    /// Slot (start-of-day + hour/minute) already shown, so repeated fetches
    /// within the window don't stack duplicate cards. The activity itself is
    /// never held: it's ended immediately with a delayed dismissal date.
    private var shownSlotKey: Date?

    private init() {}

    /// Reconcile with the latest forecast. Called after every successful
    /// weather fetch — it only acts inside a forecast-slot window.
    func update(with weather: WeatherInfo) {
        guard enabled else { return }

        guard let slot = Self.activeSlot(now: Date()) else { return }
        guard shownSlotKey != slot else { return }
        guard let today = weather.dailyForecast.first else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = DailySummaryActivityAttributes(cityName: weather.location.city, dayLabel: "Today")
        let state = DailySummaryActivityAttributes.ContentState(
            conditionText: today.condition,
            highLowText: "H \(today.highTemp) · L \(today.lowTemp)",
            rainChanceText: today.chanceOfRain.map { "\($0) rain" }
        )

        do {
            let requested = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: Date().addingTimeInterval(Self.startWindow)),
                pushType: nil
            )
            shownSlotKey = slot
            // Self-dismiss: end immediately with a delayed dismissal date — the
            // card shows its final content until then, no updates needed.
            let dismissalDate = Date().addingTimeInterval(dismissalDelay)
            Task {
                await requested.end(
                    .init(state: state, staleDate: nil),
                    dismissalPolicy: .after(dismissalDate)
                )
            }
        } catch {
            // Not authorized / out of budget — skip this slot.
        }
    }

    /// The card dismisses itself; nothing is held to retract.
    func end() {}

    private var enabled: Bool {
        UserDefaults.standard.object(forKey: "Breezy.dailySummaryLiveActivityEnabled") as? Bool ?? true
    }

    /// The current forecast slot if `now` falls within its start window:
    /// the start-of-day anchored date for hour/minute. Nil otherwise.
    static func activeSlot(now: Date, settings: NotificationSettings = UserDefaults.standard.notificationSettings) -> Date? {
        guard settings.dailyForecastEnabled else { return nil }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)

        return settings.dailyForecastTimes
            .compactMap { time in
                var components = calendar.dateComponents([.year, .month, .day], from: startOfToday)
                components.hour = time.hour
                components.minute = time.minute
                return calendar.date(from: components)
            }
            .first { slot in
                let elapsed = now.timeIntervalSince(slot)
                return elapsed >= 0 && elapsed <= startWindow
            }
    }
}
