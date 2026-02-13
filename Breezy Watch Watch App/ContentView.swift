//
//  ContentView.swift
//  Breezy Watch Watch App
//
//  Main watch app view - Vertical Paging Layout
//

import SwiftUI
import WatchKit
import Charts

struct ContentView: View {
    @EnvironmentObject var viewModel: WatchWeatherViewModel
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Global Background
                if let weather = viewModel.weather {
                    let theme = viewModel.currentTheme(isSystemDark: colorScheme == .dark)
                    LinearGradient(
                        gradient: Gradient(colors: [theme.topColor, theme.bottomColor]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                } else if let cachedCond = UserDefaults(suiteName: "group.com.breezy.weather")?.string(forKey: "WatchLastCondition") {
                    let theme = viewModel.theme(for: cachedCond, isSystemDark: colorScheme == .dark)
                    LinearGradient(
                        gradient: Gradient(colors: [theme.topColor, theme.bottomColor]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                } else {
                    let theme = viewModel.currentTheme(isSystemDark: colorScheme == .dark)
                    LinearGradient(
                        gradient: Gradient(colors: [theme.topColor, theme.bottomColor]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                }
                
                // Main Content
                if let weather = viewModel.weather {
                    TabView {
                        CurrentOverviewView(weather: weather)
                            .containerBackground(Color.clear, for: .tabView)
                        
                        DailyForecastView(daily: weather.dailyForecast)
                            .containerBackground(Color.clear, for: .tabView)
                    }
                    .tabViewStyle(.page)
                } else if viewModel.locationAuthorizationStatus == .notDetermined {
                    LocationPermissionView(viewModel: viewModel)
                } else if viewModel.isLoading {
                    LoadingView()
                } else if let error = viewModel.error {
                    ErrorView(error: error, viewModel: viewModel)
                } else {
                    NoDataView()
                }
            }
            .refreshable {
                await viewModel.loadWeather()
            }
        }
        .onAppear {
            Task {
                await viewModel.loadWeather()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await viewModel.loadWeather()
                }
            }
        }
    }
}

// MARK: - Page 1: Current Overview (Customizable)
struct CurrentOverviewView: View {
    let weather: WatchWeatherData
    @EnvironmentObject var viewModel: WatchWeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        let theme = viewModel.theme(for: weather.condition, isSystemDark: colorScheme == .dark)
        
        ScrollView {
            VStack(spacing: 12) {
                // Pinned Header
                MainInfoSection(weather: weather, theme: theme, viewModel: viewModel)
                
                // Reorderable Sections
                ForEach(viewModel.layoutSections) { section in
                    switch section {
                    case .header:
                        EmptyView() // Should not happen
                    case .hourly:
                        HourlyForecastHorizontalView(hourly: weather.hourlyForecast, isMinimalist: viewModel.useMinimalistIcons, textColor: theme.textColor)
                            .padding(.top, 4)
                    case .metrics:
                        MetricsPillsWatchView(weather: weather)
                            .padding(.top, 4)
                    }
                }
                
                // Settings Button (always at bottom)
                NavigationLink(destination: SettingsView().environmentObject(viewModel)) {
                    Image(systemName: "gearshape.fill")
                        .font(.caption)
                        .foregroundColor(theme.textColor.opacity(0.6))
                        .padding()
                        .background(theme.textColor.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
            .padding(.horizontal)
        }
        .focusable()
    }
}

struct MainInfoSection: View {
    let weather: WatchWeatherData
    let theme: WatchWeatherTheme
    @ObservedObject var viewModel: WatchWeatherViewModel
    
    var body: some View {
        VStack(spacing: 8) {
            // City Name (Tap to change)
            NavigationLink(destination: WatchLocationPickerView().environmentObject(viewModel)) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.selectedLocationID == nil ? "location.fill" : "mappin.circle.fill")
                        .font(.system(size: 12))
                    Text(weather.city)
                        .font(.system(size: 16, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundColor(theme.textColor.opacity(0.9))
                .padding(.top, 10)
            }
            .buttonStyle(.plain)
            
            // Huge Icon
            if viewModel.useMinimalistIcons {
                Image(systemName: weather.iconName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 60))
                    .shadow(color: .white.opacity(0.2), radius: 10, x: 0, y: 0)
            } else {
                Text(weather.emoji)
                    .font(.system(size: 60))
            }
            
            // Large Thin Temperature
            Text(weather.temperature)
                .font(.system(size: 52, weight: .thin))
                .fontDesign(viewModel.typography.design)
                .foregroundColor(theme.textColor)
                .shadow(color: theme.textColor.opacity(0.1), radius: 2, x: 0, y: 1)
            
            // Feels Like
            if let feelsLike = weather.feelsLike {
                Text("Feels Like \(feelsLike)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.textColor.opacity(0.8))
            }
            
            // Condition
            Text(weather.condition)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundColor(theme.textColor.opacity(0.9))
            
            // High / Low
            if let high = weather.highTemp, let low = weather.lowTemp {
                HStack(spacing: 12) {
                    Text("H: \(high)")
                    Text("L: \(low)")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(theme.textColor.opacity(0.8))
                .padding(.top, 2)
            }
        }
    }
}

// MARK: - Page 2: Hourly Forecast


// MARK: - Page 3: Daily Forecast
struct DailyForecastView: View {
    let daily: [WatchDailyForecast]
    @EnvironmentObject var viewModel: WatchWeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        let theme = viewModel.currentTheme(isSystemDark: colorScheme == .dark)
        
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("10-DAY OUTLOOK")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(theme.textColor.opacity(0.8))
                    .padding(.top, 4)
                
                VStack(spacing: 0) {
                    let globalMin = daily.map { $0.lowValue }.min() ?? 0
                    let globalMax = daily.map { $0.highValue }.max() ?? 100
                    
                    ForEach(daily) { day in
                        NavigationLink(destination: DayDetailView(day: day).environmentObject(viewModel)) {
                            WatchDailyForecastRow(day: day, rangeLow: globalMin, rangeHigh: globalMax, isMinimalist: viewModel.useMinimalistIcons, textColor: theme.textColor)
                        }
                        .buttonStyle(.plain)
                        
                        Divider().background(theme.textColor.opacity(0.15))
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .focusable()
    }
}

// MARK: - Hour Detail View
struct HourDetailView: View {
    let hour: WatchHourlyForecast
    @EnvironmentObject var viewModel: WatchWeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        let theme = viewModel.theme(for: hour.condition, isSystemDark: colorScheme == .dark)
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [theme.topColor, theme.bottomColor]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    Text(hour.time)
                        .font(.title3.weight(.medium))
                        .foregroundColor(theme.textColor.opacity(0.9))
                        .padding(.top, 16)
                    
                    if viewModel.useMinimalistIcons {
                        Image(systemName: hour.iconName)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 70))
                            .padding(.vertical, 12)
                    } else {
                        Text(hour.emoji)
                            .font(.system(size: 60))
                            .padding(.vertical, 12)
                    }
                    
                    Text(hour.temperature)
                        .font(.system(size: 40, weight: .thin))
                        .fontDesign(viewModel.typography.design)
                        .foregroundColor(theme.textColor)
                    
                    Text(hour.condition)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(theme.textColor.opacity(0.9))
                        .padding(.top, 4)
                }
                .padding()
            }
            .focusable()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Helper Views (State)

struct LocationPermissionView: View {
    @ObservedObject var viewModel: WatchWeatherViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "location.fill")
                .font(.system(size: 36))
                .foregroundColor(.white.opacity(0.8))
            
            Text("Location Needed")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white)
            
            Text("Breezy needs your location to show weather.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            
            Button("Allow Location") {
                Task {
                    await viewModel.loadWeather()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.9))
            .font(.caption2)
        }
        .padding()
    }
}

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(.white)
            Text("Loading weather...")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
        }
        .padding()
    }
}

struct ErrorView: View {
    let error: String
    @ObservedObject var viewModel: WatchWeatherViewModel
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.6))
            Text("Error")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.8))
            Text(error)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            Button("Retry") {
                Task {
                    await viewModel.loadWeather()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.8))
            .font(.caption2)
        }
        .padding()
    }
}

struct NoDataView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "cloud")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.6))
            Text("No weather data")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.8))
            Text("Pull to refresh")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchWeatherViewModel())
}
