//
//  FloatingParticles.swift
//  Breezy
//
//  Ambient floating orbs for background atmosphere
//

import SwiftUI

struct FloatingParticles: View {
    @State private var animate = false
    let particleCount: Int = 4
    
    var body: some View {
        ZStack {
            ForEach(0..<particleCount, id: \.self) { index in
                FloatingOrb(
                    size: CGFloat.random(in: 40...120),
                    opacity: Double.random(in: 0.15...0.35),
                    xOffset: CGFloat.random(in: -150...150),
                    yOffset: CGFloat.random(in: -300...300),
                    animationDelay: Double(index) * 0.5,
                    color: orbColor(for: index)
                )
            }
        }
        .onAppear {
            animate = true
        }
    }
    
    private func orbColor(for index: Int) -> Color {
        let colors: [Color] = [
            DesignSystem.softBlue,
            DesignSystem.lavender,
            DesignSystem.softPink,
            DesignSystem.lightPeach,
            .white
        ]
        return colors[index % colors.count]
    }
}

struct FloatingOrb: View {
    let size: CGFloat
    let opacity: Double
    let xOffset: CGFloat
    let yOffset: CGFloat
    let animationDelay: Double
    let color: Color
    
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        color.opacity(opacity),
                        color.opacity(opacity * 0.3),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .blur(radius: 20)
            .offset(
                x: isAnimating ? xOffset + 30 : xOffset - 30,
                y: isAnimating ? yOffset + 50 : yOffset - 50
            )
            .animation(
                Animation
                    .easeInOut(duration: Double.random(in: 8...15))
                    .repeatForever(autoreverses: true)
                    .delay(animationDelay),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
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
        
        FloatingParticles()
    }
    .ignoresSafeArea()
}
