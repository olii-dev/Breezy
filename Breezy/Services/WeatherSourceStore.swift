//
//  WeatherSourceStore.swift
//  Breezy
//
//  Persists the active weather provider across app, widgets, and watch.
//

import Foundation

extension Notification.Name {
    static let breezyWeatherSourceChanged = Notification.Name("BreezyWeatherSourceChanged")
}

enum WeatherSourceStore {
    static let storageKey = "Breezy.weatherSource"
    static let appGroup = "group.com.breezy.weather"

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    static var selectedSource: WeatherSource {
        get {
            if let raw = UserDefaults.standard.string(forKey: storageKey),
               let source = WeatherSource(rawValue: raw) {
                return source
            }

            if let raw = sharedDefaults?.string(forKey: storageKey),
               let source = WeatherSource(rawValue: raw) {
                UserDefaults.standard.set(raw, forKey: storageKey)
                return source
            }

            return .weatherKit
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
            sharedDefaults?.set(newValue.rawValue, forKey: storageKey)
            sharedDefaults?.synchronize()
            NotificationCenter.default.post(name: .breezyWeatherSourceChanged, object: newValue)
        }
    }
}
