//
//  WeatherCache.swift
//  Breezy
//
//  Weather data caching
//

import Foundation

struct WeatherCache {
    private static let key = "Breezy.WeatherCacheV3"
    
    static func save(_ weather: WeatherInfo) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(weather) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    static func load() -> WeatherInfo? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(WeatherInfo.self, from: data)
    }
    
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

