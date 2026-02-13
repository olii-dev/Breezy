//
//  DesignSystem.swift
//  Breezy
//
//  Modern design system for the app - Weather Mini aesthetic
//

import SwiftUI
import Combine

struct DesignSystem {
    // MARK: - Pastel Color Palette
    
    // Soft gradient colors
    static let softBlue = Color(red: 0.72, green: 0.83, blue: 0.95)      // #B8D4F1
    static let lavender = Color(red: 0.83, green: 0.77, blue: 0.98)      // #D4C4FB
    static let softPink = Color(red: 0.97, green: 0.77, blue: 0.85)      // #F8C4D8
    static let lightPeach = Color(red: 1.0, green: 0.89, blue: 0.8)      // #FFE4CC
    static let paleYellow = Color(red: 1.0, green: 0.95, blue: 0.8)      // #FFF2CC
    static let mintGreen = Color(red: 0.8, green: 0.95, blue: 0.9)       // #CCF2E5
    
    // Accent colors
    static let softOrange = Color(red: 1.0, green: 0.85, blue: 0.6)      // #FFD999
    static let skyBlue = Color(red: 0.6, green: 0.85, blue: 1.0)         // #99D9FF
    
    // MARK: - Spacing (increased for more breathing room)
    
    static let spacingXS: CGFloat = 6
    static let spacingS: CGFloat = 12
    static let spacingM: CGFloat = 20
    static let spacingL: CGFloat = 28
    static let spacingXL: CGFloat = 36
    static let spacingXXL: CGFloat = 52
    
    // MARK: - Corner Radius (softer, rounder)
    
    static let radiusS: CGFloat = 16
    static let radiusM: CGFloat = 20
    static let radiusL: CGFloat = 28
    static let radiusXL: CGFloat = 36
    
    // MARK: - Shadows (much softer)
    
    static let shadowSoft = Shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
    static let shadowMedium = Shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
    static let shadowLarge = Shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
    
    // MARK: - Glass Effect (ultra-subtle)
    
    static func softGlassMaterial(opacity: Double = 0.15) -> some View {
        Rectangle()
            .fill(.ultraThinMaterial.opacity(opacity))
    }
}

struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - Soft Glass Card Style

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
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
    }
}

extension View {
    func softGlassCard(padding: CGFloat = 20, cornerRadius: CGFloat = 20) -> some View {
        modifier(SoftGlassCard(padding: padding, cornerRadius: cornerRadius))
    }
    
    // Keep old modernCard for backward compatibility during transition
    func modernCard(padding: CGFloat = 20, cornerRadius: CGFloat = 24) -> some View {
        modifier(ModernCard(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - Legacy Modern Card (for backward compatibility)

struct ModernCard: ViewModifier {
    let padding: CGFloat
    let cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial.opacity(0.4))
            .cornerRadius(cornerRadius)
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Pastel Gradient Background

struct PastelGradientBackground: View {
    let colors: [Color]
    
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: colors),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

// MARK: - Legacy AnimatedGradientBackground (for backward compatibility)

struct AnimatedGradientBackground: View {
    let colors: [Color]
    
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: colors),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}


// MARK: - Jiggle Effect for Edit Mode

struct JiggleModifier: ViewModifier {
    let isJiggling: Bool
    @State private var isAnimating = false
    @State private var rotationOffset: Double = Double.random(in: -0.5...0.5)
    @State private var xOffset: CGFloat = CGFloat.random(in: -0.5...0.5)
    @State private var yOffset: CGFloat = CGFloat.random(in: -0.5...0.5)
    
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isJiggling ? (isAnimating ? 1.2 + rotationOffset : -1.2 - rotationOffset) : 0))
            .offset(
                x: isJiggling ? (isAnimating ? xOffset : -xOffset) : 0,
                y: isJiggling ? (isAnimating ? yOffset : -yOffset) : 0
            )
            .onAppear {
                if isJiggling {
                    startAnimation()
                }
            }
            .onChange(of: isJiggling) { _, newValue in
                if newValue {
                    startAnimation()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isAnimating = false
                    }
                }
            }
    }
    
    private func startAnimation() {
        withAnimation(Animation.easeInOut(duration: 0.12).repeatForever(autoreverses: true)) {
            isAnimating = true
        }
    }
}

extension View {
    func jiggle(enabled: Bool) -> some View {
        modifier(JiggleModifier(isJiggling: enabled))
    }
}
