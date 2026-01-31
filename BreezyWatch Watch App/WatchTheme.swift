//
//  WatchTheme.swift
//  BreezyWatch Watch App
//
//  Ported theme logic for WatchOS
//

import SwiftUI

// Watch-compatible Color extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct WatchTheme {
    let topColor: Color
    let bottomColor: Color
    let textColor: Color
    
    struct PresetTheme {
        let name: String
        let light: WatchTheme
        let dark: WatchTheme
    }
    
    // Exact copy of iOS presets
    static let presets: [PresetTheme] = [
        PresetTheme(
            name: "Cotton Candy",
            light: WatchTheme(topColor: Color(hex: "ffc3a0"), bottomColor: Color(hex: "ffafbd"), textColor: Color(hex: "5e4b56")),
            dark: WatchTheme(topColor: Color(hex: "AA6373"), bottomColor: Color(hex: "8B4F60"), textColor: .white)
        ),
        PresetTheme(
            name: "Ocean",
            light: WatchTheme(topColor: Color(hex: "2193b0"), bottomColor: Color(hex: "6dd5ed"), textColor: .white),
            dark: WatchTheme(topColor: Color(hex: "0f415c"), bottomColor: Color(hex: "2a5298"), textColor: .white)
        ),
        PresetTheme(
            name: "Forest",
            light: WatchTheme(topColor: Color(hex: "71b280"), bottomColor: Color(hex: "134e5e"), textColor: .white),
            dark: WatchTheme(topColor: Color(hex: "1d4e2a"), bottomColor: Color(hex: "0b2b26"), textColor: .white)
        ),
        PresetTheme(
            name: "Sunset",
            light: WatchTheme(topColor: Color(hex: "ff512f"), bottomColor: Color(hex: "dd2476"), textColor: .white),
            dark: WatchTheme(topColor: Color(hex: "8E2424"), bottomColor: Color(hex: "591B3C"), textColor: .white)
        ),
        PresetTheme(
            name: "Midnight",
            light: WatchTheme(topColor: Color(hex: "8e9eab"), bottomColor: Color(hex: "eef2f3"), textColor: Color(hex: "2c3e50")),
            dark: WatchTheme(topColor: Color(hex: "232526"), bottomColor: Color(hex: "414345"), textColor: .white)
        ),
        PresetTheme(
            name: "Lavender",
            light: WatchTheme(topColor: Color(hex: "E0C3FC"), bottomColor: Color(hex: "8EC5FC"), textColor: Color(hex: "4A4A4A")),
            dark: WatchTheme(topColor: Color(hex: "563C80"), bottomColor: Color(hex: "3A3F70"), textColor: .white)
        ),
        PresetTheme(
            name: "Royal",
            light: WatchTheme(topColor: Color(hex: "536976"), bottomColor: Color(hex: "292E49"), textColor: .white),
            dark: WatchTheme(topColor: Color(hex: "141E30"), bottomColor: Color(hex: "243B55"), textColor: .white)
        ),
        PresetTheme(
            name: "Mango",
            light: WatchTheme(topColor: Color(hex: "ffe259"), bottomColor: Color(hex: "ffa751"), textColor: Color(hex: "5e4b56")),
            dark: WatchTheme(topColor: Color(hex: "B37E22"), bottomColor: Color(hex: "8C4E16"), textColor: .white)
        )
    ]
}
