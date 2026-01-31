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
    }
}

