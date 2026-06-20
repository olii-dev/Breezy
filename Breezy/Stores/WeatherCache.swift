//
//  WeatherCache.swift
//  Breezy
//
//  Weather data caching
//

import Foundation

struct WeatherCache {
    private static let keyPrefix = "Breezy.WeatherCacheV4"

    private static func key(for source: WeatherSource) -> String {
        "\(keyPrefix).\(source.rawValue)"
    }
    
    static func save(_ weather: WeatherInfo, source: WeatherSource = WeatherSourceStore.selectedSource) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(weather) {
            UserDefaults.standard.set(data, forKey: key(for: source))
        }
    }
    
    static func load(source: WeatherSource = WeatherSourceStore.selectedSource) -> WeatherInfo? {
        guard let data = UserDefaults.standard.data(forKey: key(for: source)) else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(WeatherInfo.self, from: data)
    }
    
    static func clear(source: WeatherSource? = nil) {
        if let source {
            UserDefaults.standard.removeObject(forKey: key(for: source))
            return
        }

        WeatherSource.allCases.forEach { sourceCase in
            UserDefaults.standard.removeObject(forKey: key(for: sourceCase))
        }
    }
}
