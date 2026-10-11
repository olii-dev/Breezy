//
//  BackgroundRefreshManager.swift
//  Breezy Watch Watch App
//
//  Manages background refresh to keep widget data up-to-date
//

import Foundation
import WidgetKit
#if os(watchOS)
import WatchKit
#endif

@MainActor
class BackgroundRefreshManager {
    static let shared = BackgroundRefreshManager()
    
    private init() {}
    
    func setupBackgroundRefresh() {
        #if os(watchOS)
        scheduleBackgroundTask()
        #endif
    }
    
    #if os(watchOS)
    func scheduleBackgroundTask() {
        let defaults = UserDefaults(suiteName: "group.com.breezy.weather")
        let interval = defaults?.integer(forKey: "WatchRefreshInterval") ?? 15
        
        let when = Date().addingTimeInterval(TimeInterval(interval * 60))
        
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: when,
            userInfo: nil
        ) { _ in }
    }
    
    func handleBackgroundRefresh(_ backgroundTasks: Set<WKRefreshBackgroundTask>) async {
        for task in backgroundTasks {
            if let refreshTask = task as? WKApplicationRefreshBackgroundTask {
                // Refresh weather data
                await refreshWeatherData()
                
                // Reschedule for next time
                scheduleBackgroundTask()
                
                // Mark task as completed
                refreshTask.setTaskCompletedWithSnapshot(false)
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
    #endif
    
    private func refreshWeatherData() async {
        do {
            let data = try await WatchWeatherDataService.shared.refreshStoredSelectionWeather()
            // Wrist alerts: only when the iPhone can't mirror its own.
            WatchNotificationManager.shared.runChecks(
                weather: data,
                phoneReachable: WatchSessionManager.shared.isPhoneReachable
            )
            WatchNotificationManager.shared.refreshDailyForecastSchedule(weather: data)
        } catch {
            // Keep the cached forecast; the next refresh retries.
        }

        // Reload widget timelines
        WidgetCenter.shared.reloadAllTimelines()
    }
}
