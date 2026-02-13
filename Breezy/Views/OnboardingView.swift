//
//  OnboardingView.swift
//  Breezy
//
//  Onboarding tutorial view
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @ObservedObject var viewModel: WeatherViewModel
    @ObservedObject var locationHelper: LocationHelper
    @Environment(\.colorScheme) var colorScheme
    @State private var currentPage = 0
    
    var body: some View {
        ZStack {
            let theme = viewModel.currentTheme(colorScheme: colorScheme)
            AnimatedGradientBackground(
                colors: [theme.topColor, theme.bottomColor]
            )
            .ignoresSafeArea()
            
            TabView(selection: $currentPage) {
                // Page 1: Welcome
                OnboardingPage(
                    content: WelcomeLabel(textColor: theme.textColor),
                    title: "Weather, re-imagined",
                    description: "Experience the forecast like never before with beautiful animations and a customisable interface.",
                    buttonText: "Let's Go",
                    textColor: theme.textColor,
                    action: { withAnimation { currentPage = 1 } }
                )
                .tag(0)
                
                // Page 2: Adaptive Themes
                OnboardingPage(
                    content: ThemeMockupView(),
                    title: "Adaptive Themes",
                    description: "Breezy shifts its personality with the weather. From vibrant sunsets to cool rainy mornings, the app always feels right.",
                    buttonText: "That's Cool",
                    textColor: theme.textColor,
                    action: { withAnimation { currentPage = 2 } }
                )
                .tag(1)
                
                // Page 3: Design Studio
                OnboardingPage(
                    content: WidgetMockupView(),
                    title: "Design Studio",
                    description: "Your dashboard, your rules. Build a custom layout that shows exactly what you need, exactly where you want it.",
                    buttonText: "Next",
                    textColor: theme.textColor,
                    action: { withAnimation { currentPage = 3 } }
                )
                .tag(2)
                
                // Page 4: Time Machine
                OnboardingPage(
                    content: TimeMachineMockupView(),
                    title: "Time Machine",
                    description: "Travel through time to see historical weather data. Compare different years side-by-side to see how the climate is shifting.",
                    buttonText: "Incredible",
                    textColor: theme.textColor,
                    action: { withAnimation { currentPage = 4 } }
                )
                .tag(3)
                
                // Page 5: Advanced Visuals
                OnboardingPage(
                    content: AstroMockupView(),
                    title: "Advanced Visuals",
                    description: "Deep data at a glance. Track the sun's path, moon phases, and UV index with bespoke visualizations.",
                    buttonText: "Next",
                    textColor: theme.textColor,
                    action: { withAnimation { currentPage = 5 } }
                )
                .tag(4)
                
                // Page 6: Location
                OnboardingPage(
                    content: Image(systemName: "location.circle.fill").font(.system(size: 100)).foregroundColor(theme.textColor),
                    title: "Always Accurate",
                    description: "Breezy needs your location to provide local forecasts. We never share your data—it's just for the weather.",
                    buttonText: "Enable Location",
                    textColor: theme.textColor,
                    action: {
                        Task {
                            _ = try? await locationHelper.requestLocationAndGetData()
                            withAnimation { currentPage = 6 }
                        }
                    }
                )
                .tag(5)
                
                // Page 7: Notifications
                OnboardingPage(
                    content: Image(systemName: "bell.badge.fill").font(.system(size: 100)).foregroundColor(theme.textColor),
                    title: "Stay Informed",
                    description: "Get alerts for severe weather and rain so you're never caught off guard. You can customise these any time.",
                    buttonText: "Enable Notifications",
                    textColor: theme.textColor,
                    action: {
                        Task {
                            _ = await NotificationManager.shared.requestAuthorization()
                            withAnimation { currentPage = 7 }
                        }
                    }
                )
                .tag(6)
                
                // Page 8: Get Started
                OnboardingPage(
                    content: Image(systemName: "hand.tap.fill").font(.system(size: 100)).foregroundColor(theme.textColor),
                    title: "Ready to Breeze?",
                    description: "You're all set up. Welcome to the most customisable weather experience on iOS.",
                    buttonText: "Start Exploring",
                    textColor: theme.textColor,
                    action: { completeOnboarding() }
                )
                .tag(7)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
    }
    
    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "Breezy.HasCompletedOnboarding")
        isPresented = false
    }
}

struct WelcomeLabel: View {
    let textColor: Color
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "cloud.sun.fill")
                .font(.system(size: 100))
                .foregroundColor(textColor)
                .symbolRenderingMode(.hierarchical)
            Text("Breezy")
                .font(.system(size: 48, weight: .black, design: .rounded))
                .foregroundColor(textColor)
        }
    }
}

struct OnboardingPage<Content: View>: View {
    let content: Content
    let title: String
    let description: String
    let buttonText: String
    let textColor: Color
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            content
                .frame(height: 350)
            
            Spacer()
            
            VStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(textColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(textColor.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.bottom, 40)
            
            Button(action: {
                HapticsManager.shared.impact(style: .medium)
                action()
            }) {
                Text(buttonText)
                    .font(.headline)
                    .foregroundColor(colorScheme == .light ? .white : .black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                            .fill(textColor)
                            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                    )
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
    }
}

struct OnboardingPageWithSkip: View {
    let icon: String
    let title: String
    let description: String
    let buttonText: String
    let textColor: Color
    let action: () -> Void
    let skipAction: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 180, height: 180)
                    .blur(radius: 40)
                Image(systemName: icon)
                    .font(.system(size: 80))
                    .foregroundColor(textColor)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
            }
            
            VStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(textColor)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(textColor.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
            
            VStack(spacing: 12) {
                Button(action: action) {
                    Text(buttonText)
                        .font(.headline)
                        .foregroundColor(colorScheme == .light ? .white : .black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                                .fill(textColor)
                                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
                        )
                }
                .accessibilityLabel(buttonText)
                
                Button(action: skipAction) {
                    Text("Skip for Now")
                        .font(.subheadline)
                        .foregroundColor(textColor.opacity(0.7))
                }
                .accessibilityLabel("Skip for now")
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
    }
}
