//
//  LiveActivityHub.swift
//  Breezy
//
//  One entry point that reconciles every weather Live Activity with a fresh
//  forecast — used by the ViewModel after each fetch and by the background
//  refresh task.
//

import Foundation
import os.log

@MainActor
enum LiveActivityHub {
    private static let logger = Logger(subsystem: "com.breezy.weather", category: "liveactivities")

    static func updateAll(with weather: WeatherInfo) {
        #if DEBUG
        logger.debug("updateAll: \(weather.condition, privacy: .public) @ \(weather.location.city, privacy: .public)")
        #endif
        RainLiveActivityManager.shared.update(with: weather)
        UVLiveActivityManager.shared.update(with: weather)
        SevereWeatherLiveActivityManager.shared.update(with: weather)
        WindLiveActivityManager.shared.update(with: weather)
        DailySummaryLiveActivityManager.shared.update(with: weather)
    }

    /// Dismiss every weather Live Activity — used when fresh data is
    /// unavailable (offline / no location) so restored activities can't
    /// squat on the Lock Screen asserting saved weather.
    static func endAll() {
        RainLiveActivityManager.shared.end()
        UVLiveActivityManager.shared.end()
        SevereWeatherLiveActivityManager.shared.end()
        WindLiveActivityManager.shared.end()
        AuroraLiveActivityManager.shared.end()
    }

    /// Soonest staleDate across the weather activities — the moment the
    /// Lock Screen would start showing stale data, so background wakes can
    /// land just before it.
    static func earliestStaleDate() -> Date? {
        [
            RainLiveActivityManager.shared.activeStaleDate,
            UVLiveActivityManager.shared.activeStaleDate,
            SevereWeatherLiveActivityManager.shared.activeStaleDate,
            WindLiveActivityManager.shared.activeStaleDate,
            AuroraLiveActivityManager.shared.activeStaleDate,
        ]
        .compactMap { $0 }
        .min()
    }

    /// Re-adopt still-running activities after a process restart, so a
    /// relaunched app can update and dismiss them again. Called at launch.
    static func restoreAll() {
        RainLiveActivityManager.shared.restore()
        UVLiveActivityManager.shared.restore()
        SevereWeatherLiveActivityManager.shared.restore()
        WindLiveActivityManager.shared.restore()
        TripLiveActivityManager.shared.restore()
        AuroraLiveActivityManager.shared.restore()
    }
}
