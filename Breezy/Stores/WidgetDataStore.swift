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
    private static let keyPrefix = "BreezyWidgetData"
    private static let lastRefreshPrefix = "BreezyLastRefresh"

    private static func key(for source: WeatherSource) -> String {
        "\(keyPrefix).\(source.rawValue)"
    }

    private static func lastRefreshKey(for source: WeatherSource) -> String {
        "\(lastRefreshPrefix).\(source.rawValue)"
    }
    
    static func isDataFresh(for source: WeatherSource = WeatherSourceStore.selectedSource) -> Bool {
        guard let defaults = UserDefaults.shared,
              let lastRefresh = defaults.object(forKey: lastRefreshKey(for: source)) as? Date else {
            return false
        }
        let freshnessInterval: TimeInterval = 30 * 60 // 30 minutes
        return Date().timeIntervalSince(lastRefresh) < freshnessInterval
    }
    
    static func markRefreshed(source: WeatherSource = WeatherSourceStore.selectedSource) {
        UserDefaults.shared?.set(Date(), forKey: lastRefreshKey(for: source))
    }
    
    static func save(_ data: WidgetWeatherData, source: WeatherSource = WeatherSourceStore.selectedSource) {
        guard let defaults = UserDefaults.shared else {
            print("❌ WidgetDataStore: Failed to access App Group")
            return
        }
        
        let encoder = JSONEncoder()
        guard let encoded = try? encoder.encode(data) else {
            print("❌ WidgetDataStore: Failed to encode widget data")
            return
        }
        
        defaults.set(encoded, forKey: key(for: source))
        defaults.set(Date(), forKey: lastRefreshKey(for: source))
        defaults.synchronize()
        
        print("✅ WidgetDataStore: Saved weather for \(data.city) at \(data.timestamp)")
        print("🔄 WidgetDataStore: Calling reloadAllTimelines()")
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    static func load(source: WeatherSource = WeatherSourceStore.selectedSource) -> WidgetWeatherData? {
        guard let defaults = UserDefaults.shared else {
            return nil
        }
        
        guard let data = defaults.data(forKey: key(for: source)) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        return try? decoder.decode(WidgetWeatherData.self, from: data)
    }
    
    static func clear(source: WeatherSource? = nil) {
        if let source {
            UserDefaults.shared?.removeObject(forKey: key(for: source))
            UserDefaults.shared?.removeObject(forKey: lastRefreshKey(for: source))
            return
        }

        WeatherSource.allCases.forEach { sourceCase in
            UserDefaults.shared?.removeObject(forKey: key(for: sourceCase))
            UserDefaults.shared?.removeObject(forKey: lastRefreshKey(for: sourceCase))
        }
    }
}
