//
//  AnimatedWeatherIcon.swift
//  Breezy
//
//  Weather icons with gradient styling (static, no animations)
//

import SwiftUI

struct AnimatedWeatherIcon: View {
    let systemName: String
    let size: CGFloat
    let condition: String
    var colorScheme: ColorScheme? = nil
    
    @Environment(\.colorScheme) var systemColorScheme
    
    private var effectiveColorScheme: ColorScheme {
        colorScheme ?? systemColorScheme
    }
    
    var body: some View {
        ZStack {
            // Shadow layer
            Image(systemName: systemName)
                .font(.system(size: size, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.black.opacity(0.15), Color.black.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .offset(y: 3)
                .blur(radius: 4)
            
            // Main icon with gradient
            Image(systemName: systemName)
                .font(.system(size: size, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: iconGradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolRenderingMode(.hierarchical)
        }
    }
    
    // MARK: - Gradient Colors
    
    private var iconGradientColors: [Color] {
        let lowerCondition = condition.lowercased()
        let isLight = effectiveColorScheme == .light
        
        if lowerCondition.contains("sun") || lowerCondition.contains("clear") {
            return [DesignSystem.softOrange, DesignSystem.paleYellow]
        } else if lowerCondition.contains("cloud") {
            // Cloud needs more contrast in light mode against light backgrounds
            if isLight {
                return [Color(white: 0.6), DesignSystem.softBlue]
            } else {
                return [Color.white, DesignSystem.softBlue]
            }
        } else if lowerCondition.contains("rain") || lowerCondition.contains("drizzle") {
            return [DesignSystem.skyBlue, DesignSystem.lavender]
        } else if lowerCondition.contains("snow") {
            // Snow needs SIGNIFICANT contrast in light mode (often white background)
            if isLight {
                return [Color(hex: "A0A0A0"), DesignSystem.softBlue] // Greyish blue
            } else {
                return [Color.white, DesignSystem.softBlue.opacity(0.8)]
            }
        } else if lowerCondition.contains("storm") || lowerCondition.contains("thunder") {
            return [DesignSystem.lavender, Color.purple.opacity(0.6)]
        } else {
            if isLight {
                return [Color(white: 0.7), DesignSystem.softBlue]
            } else {
                return [Color.white, DesignSystem.softBlue]
            }
        }
    }
}
// Helper for hex color just in case it's not in DesignSystem
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

// MARK: - Emoji Icon (static)

struct EmojiAnimatedIcon: View {
    let emoji: String
    let size: CGFloat
    let condition: String
    
    var body: some View {
        ZStack {
            // Shadow
            Text(emoji)
                .font(.system(size: size))
                .foregroundColor(.black.opacity(0.15))
                .offset(y: 3)
                .blur(radius: 4)
            
            // Main emoji
            Text(emoji)
                .font(.system(size: size))
        }
    }
}

#Preview {
    ZStack {
        PastelGradientBackground(colors: [
            DesignSystem.softBlue,
            DesignSystem.lavender
        ])
        
        VStack(spacing: 40) {
            AnimatedWeatherIcon(systemName: "sun.max.fill", size: 120, condition: "Sunny")
            AnimatedWeatherIcon(systemName: "cloud.sun.fill", size: 100, condition: "Partly Cloudy")
            AnimatedWeatherIcon(systemName: "cloud.rain.fill", size: 100, condition: "Rain")
            AnimatedWeatherIcon(systemName: "snow", size: 100, condition: "Snow")
        }
    }
}
