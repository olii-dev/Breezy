//
//  LiveActivityHub.swift
//  Breezy
//
//  One entry point that reconciles every weather Live Activity with a fresh
//  forecast — used by the ViewModel after each fetch and by the background
//  refresh task.
//

import Foundation

@MainActor
enum LiveActivityHub {
    static func updateAll(with weather: WeatherInfo) {
        RainLiveActivityManager.shared.update(with: weather)
        UVLiveActivityManager.shared.update(with: weather)
        SevereWeatherLiveActivityManager.shared.update(with: weather)
        WindLiveActivityManager.shared.update(with: weather)
        DailySummaryLiveActivityManager.shared.update(with: weather)
    }
}
