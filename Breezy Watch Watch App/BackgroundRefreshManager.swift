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
        ) { error in
            if let error = error {
                print("❌ BackgroundRefreshManager: Failed to schedule: \(error.localizedDescription)")
            } else {
                print("📅 BackgroundRefreshManager: Scheduled for \(when)")
            }
        }
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
        print("🔄 BackgroundRefreshManager: Executing background refresh...")
        _ = try? await WatchWeatherDataService.shared.refreshStoredSelectionWeather()
        
        // Reload widget timelines
        WidgetCenter.shared.reloadAllTimelines()
    }
}
