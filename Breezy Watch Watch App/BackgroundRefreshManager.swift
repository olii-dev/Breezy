//
//  BackgroundRefreshManager.swift
//  Breezy Watch Watch App
//
//  Manages background refresh to keep widget data up-to-date
//

import Foundation

import WidgetKit

@MainActor
class BackgroundRefreshManager {
    static let shared = BackgroundRefreshManager()
    
    private let taskIdentifier = "com.breezy.weather.watch.refresh"
    private var refreshTask: Task<Void, Never>?
    
    private init() {
        setupBackgroundRefresh()
    }
    
    func setupBackgroundRefresh() {
        // Check if auto refresh is enabled
        let defaults = UserDefaults(suiteName: "group.com.breezy.weather")
        let autoRefresh = defaults?.bool(forKey: "WatchAutoRefresh") ?? true
        let interval = defaults?.integer(forKey: "WatchRefreshInterval") ?? 15
        
        if autoRefresh {
            updateRefreshSchedule(enabled: true, interval: interval)
        }
    }
    
    func updateRefreshSchedule(enabled: Bool, interval: Int) {
        // Cancel existing task
        refreshTask?.cancel()
        
        guard enabled else { return }
        
        // Schedule periodic refresh
        refreshTask = Task {
            while !Task.isCancelled {
                // Wait for the specified interval
                try? await Task.sleep(nanoseconds: UInt64(interval * 60 * 1_000_000_000))
                
                guard !Task.isCancelled else { break }
                
                // Refresh weather data
                await refreshWeatherData()
            }
        }
    }
    
    private func refreshWeatherData() async {
        // Create a temporary view model to refresh data
        let viewModel = WatchWeatherViewModel()
        await viewModel.loadWeather()
        
        // Reload widget timelines to update complications
        await MainActor.run {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    func scheduleBackgroundTask() {
        // For watchOS, we use a simpler approach with Task scheduling
        // since BackgroundTasks framework has limited support on watchOS
        setupBackgroundRefresh()
    }
}

