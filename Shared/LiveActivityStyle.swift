//
//  LiveActivityStyle.swift
//  Shared
//
//  Live Activity appearance selection — written by the app's Live Activities
//  settings, read by the widget extension on every render.
//

import Foundation
import SwiftUI

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


// MARK: - Per-activity accent colours

/// User-pickable accent per Live Activity, persisted in the app group and
/// read by every ActivityConfiguration at render time. `nil` current() means
/// "use the family default".
public enum LiveActivityAccent {
    public static let storagePrefix = "Breezy.LA."

    /// Palette order is display order. "default" clears the override.
    public static let names = ["default", "blue", "cyan", "teal", "green", "mint",
                               "yellow", "orange", "red", "pink", "purple", "indigo"]

    public static func color(for name: String) -> Color? {
        switch name {
        case "blue": return .blue
        case "cyan": return .cyan
        case "teal": return .teal
        case "green": return .green
        case "mint": return .mint
        case "yellow": return .yellow
        case "orange": return .orange
        case "red": return .red
        case "pink": return .pink
        case "purple": return .purple
        case "indigo": return .indigo
        default: return nil
        }
    }

    public static func current(activity: String) -> Color? {
        guard let name = UserDefaults(suiteName: "group.com.breezy.weather")?
            .string(forKey: storagePrefix + activity + ".accent"),
            let color = color(for: name) else { return nil }
        return color
    }

    public static func set(_ name: String?, activity: String) {
        let defaults = UserDefaults(suiteName: "group.com.breezy.weather")
        if let name, name != "default" {
            defaults?.set(name, forKey: storagePrefix + activity + ".accent")
        } else {
            defaults?.removeObject(forKey: storagePrefix + activity + ".accent")
        }
    }

    public static func storedName(activity: String) -> String {
        UserDefaults(suiteName: "group.com.breezy.weather")?
            .string(forKey: storagePrefix + activity + ".accent") ?? "default"
    }
}
