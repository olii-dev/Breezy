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
        } else if lowerCondition.contains("wind") || lowerCondition.contains("breez") {
            return [DesignSystem.softBlue, DesignSystem.skyBlue]
        } else {
            if isLight {
                return [Color(white: 0.7), DesignSystem.softBlue]
            } else {
                return [Color.white, DesignSystem.softBlue]
            }
        }
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
