//
//  LoadingSkeletonView.swift
//  Breezy
//
//  Loading skeleton views for weather data
//

import SwiftUI

struct WeatherLoadingSkeleton: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var isAnimating = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 20)
                
                // Header skeleton
                VStack(spacing: 16) {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 120, height: 120)
                        .shimmer(isAnimating: isAnimating)
                    
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 150, height: 40)
                        .shimmer(isAnimating: isAnimating)
                    
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 200, height: 24)
                        .shimmer(isAnimating: isAnimating)
                }
                .padding(.top, 40)
                
                // Chart skeleton
                VStack(alignment: .leading, spacing: 12) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 80, height: 20)
                        .shimmer(isAnimating: isAnimating)
                        .padding(.horizontal)
                    
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 200)
                        .shimmer(isAnimating: isAnimating)
                        .padding(.horizontal)
                }
                
                // Metrics skeleton
                VStack(alignment: .leading, spacing: 12) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 120, height: 20)
                        .shimmer(isAnimating: isAnimating)
                        .padding(.horizontal)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(0..<6) { _ in
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 100)
                                .shimmer(isAnimating: isAnimating)
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Forecast skeleton
                VStack(alignment: .leading, spacing: 12) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 140, height: 20)
                        .shimmer(isAnimating: isAnimating)
                        .padding(.horizontal)
                    
                    ForEach(0..<3) { _ in
                        HStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.15))
                                .frame(width: 60, height: 60)
                                .shimmer(isAnimating: isAnimating)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.2))
                                    .frame(width: 100, height: 16)
                                    .shimmer(isAnimating: isAnimating)
                                
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.15))
                                    .frame(width: 80, height: 14)
                                    .shimmer(isAnimating: isAnimating)
                            }
                            
                            Spacer()
                            
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 100, height: 20)
                                .shimmer(isAnimating: isAnimating)
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

extension View {
    func shimmer(isAnimating: Bool) -> some View {
        self.modifier(ShimmerModifier(isAnimating: isAnimating))
    }
}

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    let isAnimating: Bool
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.clear,
                            Color.white.opacity(0.3),
                            Color.clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + (geometry.size.width * 2 * phase))
                    .blur(radius: 8)
                }
            )
            .onAppear {
                if isAnimating {
                    withAnimation(
                        Animation.linear(duration: 1.5)
                            .repeatForever(autoreverses: false)
                    ) {
                        phase = 1
                    }
                }
            }
    }
}

