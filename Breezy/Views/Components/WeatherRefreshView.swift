//
//  WeatherRefreshView.swift
//  Breezy
//
//  Custom weather-themed pull-to-refresh indicator
//

import SwiftUI

struct WeatherRefreshView: View {
    @Binding var isRefreshing: Bool
    let onRefresh: () async -> Void
    @AppStorage("Breezy.glassOpacity") private var glassOpacity: Double = 0.35
    
    @State private var isAnimating = false
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                refreshIndicator
                    .frame(height: isRefreshing ? 60 : 0)
                    .opacity(isRefreshing ? 1 : 0)
                
                Color.clear
                    .frame(height: 1)
            }
            .background {
                GeometryReader { geo in
                    Color.clear
                        .preference(key: ScrollOffsetPreferenceKey.self, value: geo.frame(in: .named("scroll")).minY)
                }
            }
        }
        .coordinateSpace(name: "scroll")
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
            if value < -60 && !isRefreshing {
                Task {
                    await triggerRefresh()
                }
            }
        }
    }
    
    private var refreshIndicator: some View {
        VStack(spacing: 8) {
            if isRefreshing {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 18, weight: .semibold))
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
                        .onAppear { isAnimating = true }
                        .onDisappear { isAnimating = false }
                    
                    Text("Updating weather...")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial.opacity(glassOpacity))
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: isRefreshing)
    }
    
    private func triggerRefresh() async {
        isRefreshing = true
        HapticsManager.shared.impact(style: .medium)
        await onRefresh()
        
        try? await Task.sleep(nanoseconds: 500_000_000)
        isRefreshing = false
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    @Previewable @State var isRefreshing = false
    
    return ZStack {
        LinearGradient(colors: [.blue.opacity(0.3), .cyan.opacity(0.2)], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        
        WeatherRefreshView(isRefreshing: $isRefreshing) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
}
