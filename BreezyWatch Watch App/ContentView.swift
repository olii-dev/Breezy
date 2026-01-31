//
//  ContentView.swift
//  BreezyWatch Watch App
//
//  Main watch app view - matches iOS app design
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: WatchWeatherViewModel
    
    // Computed Font Design
    var fontDesign: Font.Design {
        switch viewModel.typography {
        case "Rounded": return .rounded
        case "Serif": return .serif
        case "Monospace": return .monospaced
        default: return .default
        }
    }

    var body: some View {
        ZStack {
            // dynamic gradient background - prioritize valid weather, fallback to cached condition? 
            // Actually, if we have a preset, we want to show it regardless of weather.
            
            // Priority 1: Direct Active Colors from Phone
            let gradientColors: [Color]
            if let active = viewModel.activeThemeColors {
                gradientColors = [Color(hex: active.top), Color(hex: active.bottom)]
            } else {
                // Priority 2: Fallback to local lookup or default
                let condition = viewModel.weather?.condition ?? "Clear" 
                gradientColors = WeatherThemeHelper.gradientColors(
                    for: condition, 
                    themeMode: viewModel.themeMode, 
                    presetName: viewModel.presetTheme
                )
            }
            
            LinearGradient(
                gradient: Gradient(colors: gradientColors),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 12) {
                    if let weather = viewModel.weather {
                        // Location
                        Text(weather.city)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.top, 4)
                        
                        // Large temperature
                        Text(weather.temperature)
                            .font(.system(size: 56, weight: .bold))
                            .fontWeight(.bold) // Redundant but safe
                            .foregroundColor(.white)
                        
                        // Weather emoji/icon
                        if viewModel.useMinimalistIcons {
                            Image(systemName: WatchIconHelper.minimalistIcon(for: weather.condition))
                                .font(.system(size: 40))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundColor(.white)
                                .padding(.vertical, 4)
                        } else {
                            Text(weather.emoji)
                                .font(.system(size: 48))
                                .padding(.vertical, 4)
                        }
                        
                        // Condition
                        Text(weather.condition)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.85))
                        
                        // High/Low
                        if let high = weather.highTemp, let low = weather.lowTemp {
                            HStack(spacing: 8) {
                                Text("H: \(high)")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.75))
                                Text("•")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.5))
                                Text("L: \(low)")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.75))
                            }
                            .padding(.top, 2)
                        }
                        
                        // Hourly Forecast
                        if !weather.hourlyForecast.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Next Hours")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.top, 8)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(weather.hourlyForecast.prefix(6), id: \.time) { hour in
                                            VStack(spacing: 4) {
                                                Text(hour.time)
                                                    .font(.caption2)
                                                    .foregroundColor(.white.opacity(0.8))
                                                
                                                if viewModel.useMinimalistIcons {
                                                    Image(systemName: WatchIconHelper.minimalistIcon(for: hour.condition))
                                                        .font(.title3)
                                                        .foregroundColor(.white)
                                                } else {
                                                    Text(hour.emoji)
                                                        .font(.title3)
                                                }
                                                
                                                Text(hour.temperature)
                                                    .font(.caption)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(.white)
                                            }
                                            .frame(width: 50)
                                            .padding(.vertical, 8)
                                            .padding(.horizontal, 6)
                                            .background(Color.white.opacity(0.15))
                                            .cornerRadius(10)
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                }
                            }
                            .padding(.top, 8)
                        }
                    } else if viewModel.isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.white)
                            Text("Loading...")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding()
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "cloud")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.6))
                            Text("No weather data")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                            Text("Open Breezy on iPhone")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding()
                    }
                    
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
            }
        }
        .overlay(alignment: .bottom) {
            // Debug Footer (Always visible on top)
            /* Removed as per user request */
        }
        .fontDesign(fontDesign) // Apply typography globally
        .refreshable {
            await viewModel.loadWeather()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
