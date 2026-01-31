//
//  WeatherThemeHelper.swift
//  Breezy Watch Watch App
//
//  Shared Design System and Theme Logic (Ported from iOS)
//

import SwiftUI

// MARK: - Design System for Watch

struct DesignSystem {
    // MARK: - Pastel Color Palette
    // (Matching iOS DesignSystem)
    
    static let softBlue = Color(red: 0.72, green: 0.83, blue: 0.95)
    static let lavender = Color(red: 0.83, green: 0.77, blue: 0.98)
    static let softPink = Color(red: 0.97, green: 0.77, blue: 0.85)
    static let lightPeach = Color(red: 1.0, green: 0.89, blue: 0.8)
    
    // Watch specific adjustments for readability if needed,
    // but starting with iOS values for consistency.
    
    // MARK: - Spacing
    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 12
    static let spacingL: CGFloat = 16
    
    // MARK: - Corner Radius
    static let radiusS: CGFloat = 12
    static let radiusM: CGFloat = 16
    static let radiusL: CGFloat = 20
    
    // MARK: - Soft Glass Material
    static func softGlassMaterial(opacity: Double = 0.15) -> some View {
        Rectangle()
            .fill(.ultraThinMaterial.opacity(opacity))
    }
}

// MARK: - Soft Glass Card Modifier

struct SoftGlassCard: ViewModifier {
    let padding: CGFloat
    let cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial.opacity(0.3))
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                }
            )
            // Shadows are expensive on Watch, use lighter or none
            // .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

extension View {
    func softGlassCard(padding: CGFloat = 12, cornerRadius: CGFloat = 16) -> some View {
        modifier(SoftGlassCard(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - Weather Theme Implementation

struct WatchWeatherTheme {
    let topColor: Color
    let bottomColor: Color
    let textColor: Color
    
    // Using Dark Mode logic primarily for Watch
    // Using Dark Mode logic primarily for Watch
    static func theme(for condition: String, isDark: Bool = true) -> WatchWeatherTheme {
        let cond = condition.lowercased()
        
        if isDark {
            // Dark / Night / Watch Logic
            if cond.contains("night") || cond.contains("clear night") || cond.contains("clear") {
                return WatchWeatherTheme(
                    topColor: Color(red: 0.25, green: 0.2, blue: 0.4),
                    bottomColor: Color(red: 0.1, green: 0.1, blue: 0.2),
                    textColor: .white
                )
            }
            if cond.contains("sun") || cond.contains("sunny") {
                return WatchWeatherTheme(
                    topColor: DesignSystem.lavender.opacity(0.6),
                    bottomColor: Color.purple.opacity(0.4),
                    textColor: .white
                )
            }
            if cond.contains("rain") || cond.contains("drizzle") {
                return WatchWeatherTheme(
                    topColor: Color(red: 0.3, green: 0.4, blue: 0.5),
                    bottomColor: Color(red: 0.2, green: 0.25, blue: 0.35),
                    textColor: .white
                )
            }
            if cond.contains("cloud") || cond.contains("overcast") {
                return WatchWeatherTheme(
                    topColor: Color(red: 0.4, green: 0.4, blue: 0.5),
                    bottomColor: Color(red: 0.3, green: 0.35, blue: 0.45),
                    textColor: .white
                )
            }
            if cond.contains("snow") || cond.contains("blizzard") {
                return WatchWeatherTheme(
                    topColor: Color(red: 0.4, green: 0.5, blue: 0.6),
                    bottomColor: Color(red: 0.3, green: 0.4, blue: 0.5),
                    textColor: .white
                )
            }
            if cond.contains("fog") || cond.contains("mist") {
                return WatchWeatherTheme(
                    topColor: Color(red: 0.35, green: 0.35, blue: 0.4),
                    bottomColor: Color(red: 0.25, green: 0.25, blue: 0.3),
                    textColor: .white
                )
            }
            return WatchWeatherTheme(
                topColor: DesignSystem.lavender.opacity(0.5),
                bottomColor: Color.indigo.opacity(0.4),
                textColor: .white
            )
        } else {
            // Light Mode Logic (Ported from iOS)
            if cond.contains("sun") || cond.contains("clear") || cond.contains("sunny") {
                return WatchWeatherTheme(
                    topColor: DesignSystem.softBlue,
                    bottomColor: DesignSystem.softPink,
                    textColor: Color(red: 0.2, green: 0.2, blue: 0.25)
                )
            }
            if cond.contains("rain") || cond.contains("drizzle") {
                return WatchWeatherTheme(
                    topColor: Color(red: 0.65, green: 0.75, blue: 0.85),
                    bottomColor: DesignSystem.lavender,
                    textColor: Color(red: 0.15, green: 0.2, blue: 0.25)
                )
            }
            if cond.contains("cloud") || cond.contains("overcast") {
                return WatchWeatherTheme(
                    topColor: Color(red: 0.8, green: 0.85, blue: 0.9),
                    bottomColor: DesignSystem.lavender,
                    textColor: Color(red: 0.2, green: 0.2, blue: 0.25)
                )
            }
            if cond.contains("snow") || cond.contains("blizzard") || cond.contains("fog") || cond.contains("mist") {
                return WatchWeatherTheme(
                    topColor: Color(red: 0.9, green: 0.95, blue: 1.0),
                    bottomColor: DesignSystem.softBlue,
                    textColor: Color(red: 0.2, green: 0.3, blue: 0.4)
                )
            }
            return WatchWeatherTheme(
                topColor: DesignSystem.softBlue,
                bottomColor: DesignSystem.lavender,
                textColor: Color(red: 0.2, green: 0.2, blue: 0.25)
            )
        }
    }
    
    // MARK: - Presets
    
    struct NamedTheme: Identifiable, Equatable {
        var id: String { name }
        let name: String
        let light: WatchWeatherTheme
        let dark: WatchWeatherTheme
        
        static func == (lhs: NamedTheme, rhs: NamedTheme) -> Bool {
            lhs.name == rhs.name
        }
    }
    
    static let presets: [NamedTheme] = [
        NamedTheme(
            name: "Cotton Candy",
            light: WatchWeatherTheme(topColor: Color(red: 1.0, green: 0.76, blue: 0.63), bottomColor: Color(red: 1.0, green: 0.69, blue: 0.74), textColor: Color(red: 0.37, green: 0.29, blue: 0.34)),
            dark: WatchWeatherTheme(topColor: Color(red: 0.67, green: 0.39, blue: 0.45), bottomColor: Color(red: 0.55, green: 0.31, blue: 0.38), textColor: .white)
        ),
        NamedTheme(
            name: "Ocean",
            light: WatchWeatherTheme(topColor: Color(red: 0.13, green: 0.58, blue: 0.69), bottomColor: Color(red: 0.43, green: 0.84, blue: 0.93), textColor: .white),
            dark: WatchWeatherTheme(topColor: Color(red: 0.06, green: 0.25, blue: 0.36), bottomColor: Color(red: 0.16, green: 0.32, blue: 0.60), textColor: .white)
        ),
        NamedTheme(
            name: "Forest",
            light: WatchWeatherTheme(topColor: Color(red: 0.44, green: 0.70, blue: 0.50), bottomColor: Color(red: 0.07, green: 0.31, blue: 0.37), textColor: .white),
            dark: WatchWeatherTheme(topColor: Color(red: 0.11, green: 0.31, blue: 0.16), bottomColor: Color(red: 0.04, green: 0.17, blue: 0.15), textColor: .white)
        ),
        NamedTheme(
            name: "Sunset",
            light: WatchWeatherTheme(topColor: Color(red: 1.0, green: 0.32, blue: 0.18), bottomColor: Color(red: 0.87, green: 0.14, blue: 0.46), textColor: .white),
            dark: WatchWeatherTheme(topColor: Color(red: 0.56, green: 0.14, blue: 0.14), bottomColor: Color(red: 0.35, green: 0.11, blue: 0.24), textColor: .white)
        ),
        NamedTheme(
            name: "Midnight",
            light: WatchWeatherTheme(topColor: Color(red: 0.56, green: 0.62, blue: 0.67), bottomColor: Color(red: 0.93, green: 0.95, blue: 0.95), textColor: Color(red: 0.17, green: 0.24, blue: 0.31)),
            dark: WatchWeatherTheme(topColor: Color(red: 0.14, green: 0.15, blue: 0.15), bottomColor: Color(red: 0.25, green: 0.26, blue: 0.27), textColor: .white)
        ),
        NamedTheme(
            name: "Lavender",
            light: WatchWeatherTheme(topColor: Color(red: 0.88, green: 0.76, blue: 0.99), bottomColor: Color(red: 0.56, green: 0.77, blue: 0.99), textColor: Color(red: 0.29, green: 0.29, blue: 0.29)),
            dark: WatchWeatherTheme(topColor: Color(red: 0.34, green: 0.24, blue: 0.50), bottomColor: Color(red: 0.23, green: 0.25, blue: 0.44), textColor: .white)
        ),
        NamedTheme(
            name: "Royal",
            light: WatchWeatherTheme(topColor: Color(red: 0.33, green: 0.41, blue: 0.46), bottomColor: Color(red: 0.16, green: 0.18, blue: 0.29), textColor: .white),
            dark: WatchWeatherTheme(topColor: Color(red: 0.08, green: 0.12, blue: 0.19), bottomColor: Color(red: 0.14, green: 0.23, blue: 0.33), textColor: .white)
        ),
        NamedTheme(
            name: "Mango",
            light: WatchWeatherTheme(topColor: Color(red: 1.0, green: 0.89, blue: 0.35), bottomColor: Color(red: 1.0, green: 0.65, blue: 0.32), textColor: Color(red: 0.37, green: 0.29, blue: 0.34)),
            dark: WatchWeatherTheme(topColor: Color(red: 0.70, green: 0.49, blue: 0.13), bottomColor: Color(red: 0.55, green: 0.31, blue: 0.09), textColor: .white)
        )
    ]
}
