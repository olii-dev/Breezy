//
//  WeatherTheme.swift
//  Breezy
//
//  Weather-based pastel theme colors
//

import SwiftUI
import UIKit

struct WeatherTheme: Codable, Identifiable {
    var id: String {
        // Generate a stable ID based on colors for custom themes, or use predefined name
        return "\(topColor.description)-\(bottomColor.description)"
    }
    
    let topColor: Color
    let bottomColor: Color
    let textColor: Color
    
    // Custom coding keys and init for Color serialization
    enum CodingKeys: String, CodingKey {
        case topColor, bottomColor, textColor
    }
    
    init(topColor: Color, bottomColor: Color, textColor: Color) {
        self.topColor = topColor
        self.bottomColor = bottomColor
        self.textColor = textColor
    }
    
    var isDark: Bool {
        // Simple heuristic: if text is light, background is likely dark
        // We convert textColor to UIColor to get brightness
        // Note: This requires UIKit import context, which is available in SwiftUI apps on iOS
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        UIColor(textColor).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let brightness = ((red * 299) + (green * 587) + (blue * 114)) / 1000
        
        // If text is bright/white (> 0.5), it's meant for a dark background -> return true (isDark theme)
        // If text is dark (< 0.5), it's meant for a light background -> return false
        return brightness > 0.5
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let topData = try container.decode(Data.self, forKey: .topColor)
        let bottomData = try container.decode(Data.self, forKey: .bottomColor)
        let textData = try container.decode(Data.self, forKey: .textColor)
        
        self.topColor = Color.fromData(topData) ?? .blue
        self.bottomColor = Color.fromData(bottomData) ?? .teal
        self.textColor = Color.fromData(textData) ?? .white
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(topColor.toData() ?? Data(), forKey: .topColor)
        try container.encode(bottomColor.toData() ?? Data(), forKey: .bottomColor)
        try container.encode(textColor.toData() ?? Data(), forKey: .textColor)
    }
    
    // Theme presets
    // Theme presets
    struct PresetTheme {
        let name: String
        let light: WeatherTheme
        let dark: WeatherTheme
    }
    
    static let presets: [PresetTheme] = [
        PresetTheme(
            name: "Cotton Candy",
            light: WeatherTheme(topColor: Color(hex: "ffc3a0"), bottomColor: Color(hex: "ffafbd"), textColor: Color(hex: "5e4b56")),
            dark: WeatherTheme(topColor: Color(hex: "AA6373"), bottomColor: Color(hex: "8B4F60"), textColor: .white)
        ),
        PresetTheme(
            name: "Ocean",
            light: WeatherTheme(topColor: Color(hex: "2193b0"), bottomColor: Color(hex: "6dd5ed"), textColor: .white),
            dark: WeatherTheme(topColor: Color(hex: "0f415c"), bottomColor: Color(hex: "2a5298"), textColor: .white)
        ),
        PresetTheme(
            name: "Forest",
            light: WeatherTheme(topColor: Color(hex: "71b280"), bottomColor: Color(hex: "134e5e"), textColor: .white),
            dark: WeatherTheme(topColor: Color(hex: "1d4e2a"), bottomColor: Color(hex: "0b2b26"), textColor: .white)
        ),
        PresetTheme(
            name: "Sunset",
            light: WeatherTheme(topColor: Color(hex: "ff512f"), bottomColor: Color(hex: "dd2476"), textColor: .white),
            dark: WeatherTheme(topColor: Color(hex: "8E2424"), bottomColor: Color(hex: "591B3C"), textColor: .white)
        ),
        PresetTheme(
            name: "Midnight",
            light: WeatherTheme(topColor: Color(hex: "8e9eab"), bottomColor: Color(hex: "eef2f3"), textColor: Color(hex: "2c3e50")), // Foggy day
            dark: WeatherTheme(topColor: Color(hex: "232526"), bottomColor: Color(hex: "414345"), textColor: .white)
        ),
        PresetTheme(
            name: "Lavender",
            light: WeatherTheme(topColor: Color(hex: "E0C3FC"), bottomColor: Color(hex: "8EC5FC"), textColor: Color(hex: "4A4A4A")),
            dark: WeatherTheme(topColor: Color(hex: "563C80"), bottomColor: Color(hex: "3A3F70"), textColor: .white)
        ),
        PresetTheme(
            name: "Royal",
            light: WeatherTheme(topColor: Color(hex: "536976"), bottomColor: Color(hex: "292E49"), textColor: .white),
            dark: WeatherTheme(topColor: Color(hex: "141E30"), bottomColor: Color(hex: "243B55"), textColor: .white)
        ),
        PresetTheme(
            name: "Mango",
            light: WeatherTheme(topColor: Color(hex: "ffe259"), bottomColor: Color(hex: "ffa751"), textColor: Color(hex: "5e4b56")),
            dark: WeatherTheme(topColor: Color(hex: "B37E22"), bottomColor: Color(hex: "8C4E16"), textColor: .white)
        )
    ]
    
    static let defaultCustom = WeatherTheme(topColor: .blue, bottomColor: .purple, textColor: .white)
    
    static func theme(for condition: String, isDark: Bool) -> WeatherTheme {
        let cond = condition.lowercased()
        
        if isDark {
            // Dark mode - still soft but with deeper tones
            if cond.contains("night") || cond.contains("clear night") || cond.contains("clear") {
                return WeatherTheme(
                    topColor: Color(red: 0.25, green: 0.2, blue: 0.4),
                    bottomColor: Color(red: 0.1, green: 0.1, blue: 0.2),
                    textColor: .white
                )
            }
            if cond.contains("sun") || cond.contains("sunny") {
                return WeatherTheme(
                    topColor: DesignSystem.lavender.opacity(0.6),
                    bottomColor: Color.purple.opacity(0.4),
                    textColor: .white
                )
            }
            if cond.contains("rain") || cond.contains("drizzle") {
                return WeatherTheme(
                    topColor: Color(red: 0.3, green: 0.4, blue: 0.5),
                    bottomColor: Color(red: 0.2, green: 0.25, blue: 0.35),
                    textColor: .white
                )
            }
            if cond.contains("cloud") || cond.contains("overcast") {
                return WeatherTheme(
                    topColor: Color(red: 0.4, green: 0.4, blue: 0.5),
                    bottomColor: Color(red: 0.3, green: 0.35, blue: 0.45),
                    textColor: .white
                )
            }
            if cond.contains("snow") || cond.contains("blizzard") {
                return WeatherTheme(
                    topColor: Color(red: 0.4, green: 0.5, blue: 0.6),
                    bottomColor: Color(red: 0.3, green: 0.4, blue: 0.5),
                    textColor: .white
                )
            }
            if cond.contains("fog") || cond.contains("mist") {
                return WeatherTheme(
                    topColor: Color(red: 0.35, green: 0.35, blue: 0.4),
                    bottomColor: Color(red: 0.25, green: 0.25, blue: 0.3),
                    textColor: .white
                )
            }
            return WeatherTheme(
                topColor: DesignSystem.lavender.opacity(0.5),
                bottomColor: Color.indigo.opacity(0.4),
                textColor: .white
            )
        } else {
            // Light mode - beautiful soft pastels
            if cond.contains("sun") || cond.contains("clear") || cond.contains("sunny") {
                return WeatherTheme(
                    topColor: DesignSystem.softBlue,
                    bottomColor: DesignSystem.softPink,
                    textColor: Color(red: 0.2, green: 0.2, blue: 0.25)
                )
            }
            if cond.contains("rain") || cond.contains("drizzle") {
                return WeatherTheme(
                    topColor: Color(red: 0.65, green: 0.75, blue: 0.85),
                    bottomColor: DesignSystem.lavender,
                    textColor: Color(red: 0.15, green: 0.2, blue: 0.25)
                )
            }
            if cond.contains("cloud") || cond.contains("overcast") {
                return WeatherTheme(
                    topColor: Color(red: 0.8, green: 0.85, blue: 0.9),
                    bottomColor: DesignSystem.lavender,
                    textColor: Color(red: 0.2, green: 0.2, blue: 0.25)
                )
            }
            if cond.contains("snow") || cond.contains("blizzard") {
                return WeatherTheme(
                    topColor: Color(red: 0.9, green: 0.95, blue: 1.0),
                    bottomColor: DesignSystem.softBlue,
                    textColor: Color(red: 0.2, green: 0.3, blue: 0.4)
                )
            }
            if cond.contains("fog") || cond.contains("mist") {
                return WeatherTheme(
                    topColor: Color(red: 0.9, green: 0.9, blue: 0.92),
                    bottomColor: Color(red: 0.95, green: 0.95, blue: 0.97),
                    textColor: Color(red: 0.3, green: 0.3, blue: 0.35)
                )
            }
            if cond.contains("storm") || cond.contains("thunder") {
                return WeatherTheme(
                    topColor: DesignSystem.lavender,
                    bottomColor: Color.purple.opacity(0.4),
                    textColor: .white // Storms can likely tolerate white text even in light mode if dark enough, or use dark purple
                )
            }
            // Default
            return WeatherTheme(
                topColor: DesignSystem.softBlue,
                bottomColor: DesignSystem.lavender,
                textColor: Color(red: 0.2, green: 0.2, blue: 0.25)
            )
        }
    }
}
