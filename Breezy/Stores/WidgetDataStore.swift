//
//  WidgetDataStore.swift
//  Breezy
//
//  Widget data sharing via App Groups
//

import Foundation
import WidgetKit

extension UserDefaults {
    static var shared: UserDefaults? {
        UserDefaults(suiteName: "group.com.breezy.weather")
    }
}

struct WidgetDataStore {
    private static let key = "BreezyWidgetData"
    private static let lastRefreshKey = "BreezyLastRefresh"
    
    static var isDataFresh: Bool {
        guard let defaults = UserDefaults.shared,
              let lastRefresh = defaults.object(forKey: lastRefreshKey) as? Date else {
            return false
        }
        let freshnessInterval: TimeInterval = 30 * 60 // 30 minutes
        return Date().timeIntervalSince(lastRefresh) < freshnessInterval
    }
    
    static func markRefreshed() {
        UserDefaults.shared?.set(Date(), forKey: lastRefreshKey)
    }
    
    static func save(_ data: WidgetWeatherData) {
        guard let defaults = UserDefaults.shared else {
            print("❌ WidgetDataStore: Failed to access App Group")
            return
        }
        
        let encoder = JSONEncoder()
        guard let encoded = try? encoder.encode(data) else {
            print("❌ WidgetDataStore: Failed to encode widget data")
            return
        }
        
        defaults.set(encoded, forKey: key)
        defaults.set(Date(), forKey: lastRefreshKey)
        defaults.synchronize()
        
        print("✅ WidgetDataStore: Saved weather for \(data.city) at \(data.timestamp)")
        print("🔄 WidgetDataStore: Calling reloadAllTimelines()")
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    static func load() -> WidgetWeatherData? {
        guard let defaults = UserDefaults.shared else {
            return nil
        }
        
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        return try? decoder.decode(WidgetWeatherData.self, from: data)
    }
    
    static func clear() {
        UserDefaults.shared?.removeObject(forKey: key)
        UserDefaults.shared?.removeObject(forKey: lastRefreshKey)
    }
}

