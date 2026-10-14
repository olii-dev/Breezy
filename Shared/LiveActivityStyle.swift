//
//  LiveActivityStyle.swift
//  Shared
//
//  Live Activity appearance selection — written by the app's Live Activities
//  settings, read by the widget extension on every render.
//

import Foundation

enum LiveActivityStyle: String {
    case darkGlass
    case matchTheme
    case pureBlack

    static var current: LiveActivityStyle {
        guard let raw = UserDefaults(suiteName: "group.com.breezy.weather")?
            .string(forKey: "Breezy.liveActivityStyle") else {
            return .darkGlass
        }
        return LiveActivityStyle(rawValue: raw) ?? .darkGlass
    }

    var displayName: String {
        switch self {
        case .darkGlass: return "Dark Glass"
        case .matchTheme: return "Match App Theme"
        case .pureBlack: return "Pure Black"
        }
    }
}
