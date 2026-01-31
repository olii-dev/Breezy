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
            
            TabView(selection: $currentPage) {
                // Page 1: Welcome
                OnboardingPage(
                    icon: "cloud.sun.fill",
                    title: "Welcome to Breezy",
                    description: "Your beautiful weather companion. Get accurate forecasts, detailed metrics, and stay informed about weather conditions.",
                    buttonText: "Next",
                    textColor: theme.textColor,
                    action: { currentPage = 1 }
                )
                .tag(0)
                
                // Page 2: Location
                OnboardingPage(
                    icon: "location.fill",
                    title: "Location Services",
                    description: "Breezy needs your location to provide accurate weather forecasts in the app, widgets, and complications. When prompted, tap 'Allow While Using App'.\n\nYour location is only used for weather data and is never shared.",
                    buttonText: "Enable Location",
                    textColor: theme.textColor,
                    action: {
                        // Request Location Permission (also enables widget location access)
                        Task {
                            _ = try? await locationHelper.requestLocationAndGetData()
                            withAnimation { currentPage = 2 }
                        }
                    }
                )
                .tag(1)
                
                // Page 3: Notifications
                OnboardingPage(
                    icon: "bell.fill",
                    title: "Weather Alerts",
                    description: "Get notified about severe weather, rain, and high UV index. When prompted, tap 'Allow' to enable notifications.\n\nYou can customize all notification settings later in the app.",
                    buttonText: "Enable Notifications",
                    textColor: theme.textColor,
                    action: {
                        // Request Notification Permission
                        Task {
                            _ = await NotificationManager.shared.requestAuthorization()
                            withAnimation { currentPage = 3 }
                        }
                    }
                )
                .tag(2)
                
                // Page 4: Widget Dashboard
                OnboardingPage(
                    icon: "square.grid.3x3.fill",
                    title: "Customizable Dashboard",
                    description: "Create your perfect weather dashboard! Add, remove, and reorder widgets right in the app. Hold any widget for 2 seconds to rearrange them however you like.",
                    buttonText: "Next",
                    textColor: theme.textColor,
                    action: { currentPage = 4 }
                )
                .tag(3)
                
                // Page 5: Time Machine
                OnboardingPage(
                    icon: "clock.arrow.circlepath",
                    title: "Time Machine",
                    description: "Travel through time to view historical weather data and future forecasts. Perfect for planning events or checking past conditions.",
                    buttonText: "Next",
                    textColor: theme.textColor,
                    action: { currentPage = 5 }
                )
                .tag(4)
                
                // Page 6: Customization
                OnboardingPage(
                    icon: "paintpalette.fill",
                    title: "Fully Customizable",
                    description: "Choose your preferred units, themes, icon styles, and more. Breezy adapts to your needs with extensive customization options in Settings.",
                    buttonText: "Get Started",
                    textColor: theme.textColor,
                    action: { completeOnboarding() }
                )
                .tag(5)
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
    }
    
    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "Breezy.HasCompletedOnboarding")
        isPresented = false
    }
}

struct OnboardingPage: View {
    let icon: String
    let title: String
    let description: String
    let buttonText: String
    let textColor: Color
    let action: () -> Void
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
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
            .accessibilityLabel(buttonText)
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
