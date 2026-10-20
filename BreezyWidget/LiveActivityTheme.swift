//
//  LiveActivityTheme.swift
//  BreezyWidgetExtension
//
//  Shared Live Activity appearance: dark glass (default), the user's app
//  theme, or pure black. Style is chosen in the app's Live Activities
//  settings and read from the shared app group on every render — activities
//  restyle automatically on their next update.
//

import SwiftUI
import UIKit

enum LiveActivityTheme {
    private struct ThemeColors {
        let top: UIColor
        let bottom: UIColor
        let text: UIColor
    }

    /// The user's selected custom/preset theme, if one is synced to the app
    /// group (same encoding as WeatherThemeHelper on the widget side).
    private static var syncedTheme: ThemeColors? {
        guard let defaults = UserDefaults(suiteName: "group.com.breezy.weather"),
              defaults.string(forKey: "Breezy.themeMode") == "Custom",
              let data = defaults.data(forKey: "Breezy.selectedCustomTheme") ?? defaults.data(forKey: "Breezy.customTheme"),
              let persisted = try? JSONDecoder().decode(PersistedTheme.self, from: data),
              let top = unarchive(persisted.topColor),
              let bottom = unarchive(persisted.bottomColor),
              let text = unarchive(persisted.textColor) else {
            return nil
        }
        return ThemeColors(top: top, bottom: bottom, text: text)
    }

    private struct PersistedTheme: Codable {
        let topColor: Data
        let bottomColor: Data
        let textColor: Data
    }

    private static func unarchive(_ data: Data) -> UIColor? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data)
    }

    private static func luminance(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    /// User-picked accent (Live Activity settings) or the family default.
    static func accent(activity: String, fallback: Color) -> Color {
        LiveActivityAccent.current(activity: activity) ?? fallback
    }

    /// Background tint for an activity. `accent` keeps per-activity identity
    /// (severe red etc.) when the user's theme isn't applicable.
    static func backgroundTint(accent: Color, isSevere: Bool = false) -> Color {
        switch LiveActivityStyle.current {
        case .darkGlass:
            return isSevere ? Color.red.opacity(0.35) : Color.black.opacity(0.4)
        case .pureBlack:
            return .black
        case .matchTheme:
            guard let theme = syncedTheme else {
                return isSevere ? Color.red.opacity(0.35) : Color.black.opacity(0.4)
            }
            return Color(uiColor: theme.top)
        }
    }

    /// Gradient variant for backgrounds that want depth.
    static func backgroundGradient() -> LinearGradient? {
        guard LiveActivityStyle.current == .matchTheme,
              let theme = syncedTheme else { return nil }
        return LinearGradient(
            colors: [Color(uiColor: theme.top), Color(uiColor: theme.bottom)],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// Primary text/action color with a legibility floor.
    static func foregroundColor() -> Color {
        switch LiveActivityStyle.current {
        case .darkGlass, .pureBlack:
            return .white
        case .matchTheme:
            guard let theme = syncedTheme else { return .white }
            // Dark text only on a clearly light background; else white.
            let bgLuma = (luminance(theme.top) + luminance(theme.bottom)) / 2
            let textLuma = luminance(theme.text)
            let contrast = (max(bgLuma, textLuma) + 0.05) / (min(bgLuma, textLuma) + 0.05)
            if bgLuma > 0.5 && contrast >= 2.6 {
                return Color(uiColor: theme.text)
            }
            return .white
        }
    }
}
