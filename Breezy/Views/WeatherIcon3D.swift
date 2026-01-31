//
//  WeatherIcon3D.swift
//  Breezy
//
//  3D-style weather icon with soft shadows
//

import SwiftUI

struct WeatherIcon3D: View {
    let systemName: String
    let size: CGFloat
    let condition: String
    
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
    
    private var iconGradientColors: [Color] {
        let lowerCondition = condition.lowercased()
        
        if lowerCondition.contains("sun") || lowerCondition.contains("clear") {
            return [DesignSystem.softOrange, DesignSystem.paleYellow]
        } else if lowerCondition.contains("cloud") {
            return [Color.white, DesignSystem.softBlue]
        } else if lowerCondition.contains("rain") || lowerCondition.contains("drizzle") {
            return [DesignSystem.skyBlue, DesignSystem.lavender]
        } else if lowerCondition.contains("snow") {
            return [Color.white, DesignSystem.softBlue.opacity(0.8)]
        } else if lowerCondition.contains("storm") || lowerCondition.contains("thunder") {
            return [DesignSystem.lavender, Color.purple.opacity(0.6)]
        } else {
            return [Color.white, DesignSystem.softBlue]
        }
    }
}

// MARK: - Emoji-Style 3D Icon

struct EmojiIcon3D: View {
    let emoji: String
    let size: CGFloat
    
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
            DesignSystem.lavender,
            DesignSystem.softPink
        ])
        
        VStack(spacing: 40) {
            WeatherIcon3D(systemName: "sun.max.fill", size: 120, condition: "Sunny")
            WeatherIcon3D(systemName: "cloud.sun.fill", size: 100, condition: "Partly Cloudy")
            WeatherIcon3D(systemName: "cloud.rain.fill", size: 100, condition: "Rain")
            EmojiIcon3D(emoji: "☀️", size: 120)
        }
    }
}
