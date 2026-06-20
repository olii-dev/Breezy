//
//  WidgetWeatherSource.swift
//  BreezyWidget
//
//  Shared provider selection for the iPhone widget extension.
//

import Foundation

enum WidgetWeatherSource: String, CaseIterable {
    case weatherKit = "weatherkit"
    case openMeteo = "open-meteo"

    static let storageKey = "Breezy.weatherSource"

    static var selected: WidgetWeatherSource {
        let defaults = UserDefaults(suiteName: "group.com.breezy.weather")
        if let raw = defaults?.string(forKey: storageKey),
           let source = WidgetWeatherSource(rawValue: raw) {
            return source
        }
        return .weatherKit
    }
}
