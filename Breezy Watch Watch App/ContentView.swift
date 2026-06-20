//
//  ContentView.swift
//  Breezy Watch Watch App
//
//  Main watch app view - Vertical Paging Layout
//

import SwiftUI
#if os(watchOS)
import WatchKit
#endif
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
                        
                        WatchChartsPageView(weather: weather)
                            .containerBackground(Color.clear, for: .tabView)
                        
                        DailyForecastView(daily: weather.dailyForecast)
                            .containerBackground(Color.clear, for: .tabView)
                        
                        WatchRadarView()
                            .containerBackground(Color.clear, for: .tabView)
                        
                        WatchTimeMachineView()
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
                    NoDataView().environmentObject(viewModel)
                }
            }
            .refreshable {
                await viewModel.refresh()
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
    @State private var doubleTapSectionIndex = 0

    private var scrollSectionIDs: [String] {
        var ids = ["header"]
        for section in viewModel.layoutSections {
            switch section {
            case .hourly:
                ids.append("hourly")
            case .metrics:
                ids.append("metrics")
            case .header:
                continue
            }
        }
        ids.append("refresh")
        ids.append("settings")
        return ids
    }
    
    var body: some View {
        let theme = viewModel.theme(for: weather.condition, isSystemDark: colorScheme == .dark)

        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    // Pinned Header
                    MainInfoSection(weather: weather, theme: theme, viewModel: viewModel)
                        .id("header")
                    
                    // Reorderable Sections
                    ForEach(viewModel.layoutSections) { section in
                        switch section {
                        case .header:
                            EmptyView() // Should not happen
                        case .hourly:
                            HourlyForecastHorizontalView(hourly: weather.hourlyForecast, isMinimalist: viewModel.useMinimalistIcons, textColor: theme.textColor)
                                .padding(.top, 4)
                                .id("hourly")
                        case .metrics:
                            MetricsPillsWatchView(weather: weather)
                                .padding(.top, 4)
                                .id("metrics")
                        }
                    }

                    Button {
                        viewModel.playHaptic(.click)
                        Task {
                            await viewModel.refresh()
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise.circle.fill")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundColor(theme.textColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(theme.textColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .id("refresh")
                    
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
                    .simultaneousGesture(TapGesture().onEnded {
                        viewModel.playHaptic(.click)
                    })
                    .padding(.top, 20)
                    .padding(.bottom, 20)
                    .id("settings")
                }
                .padding(.horizontal)
            }
            .overlay(alignment: .topTrailing) {
                WatchDoubleTapScrollTrigger {
                    scrollToNextSection(using: proxy)
                }
            }
        }
        .focusable()
    }

    private func scrollToNextSection(using proxy: ScrollViewProxy) {
        guard scrollSectionIDs.count > 1 else { return }
        let nextIndex = doubleTapSectionIndex >= scrollSectionIDs.count - 1 ? 0 : doubleTapSectionIndex + 1
        doubleTapSectionIndex = nextIndex
        withAnimation(.easeInOut(duration: 0.28)) {
            proxy.scrollTo(scrollSectionIDs[nextIndex], anchor: .top)
        }
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
            .simultaneousGesture(TapGesture().onEnded {
                viewModel.playHaptic(.click)
            })
            
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
    @State private var doubleTapSectionIndex = 0

    private var scrollSectionIDs: [String] {
        let groupedIndices = Array(stride(from: 0, to: daily.count, by: 2))
        return ["top"] + groupedIndices.map { "day-\($0)" }
    }
    
    var body: some View {
        let theme = viewModel.currentTheme(isSystemDark: colorScheme == .dark)

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("10-DAY OUTLOOK")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(theme.textColor.opacity(0.8))
                        .padding(.top, 4)
                        .id("top")
                    
                    VStack(spacing: 0) {
                        let globalMin = daily.map { $0.lowValue }.min() ?? 0
                        let globalMax = daily.map { $0.highValue }.max() ?? 100
                        
                        ForEach(Array(daily.enumerated()), id: \.element.id) { index, day in
                            NavigationLink(destination: DayDetailView(day: day).environmentObject(viewModel)) {
                                WatchDailyForecastRow(day: day, rangeLow: globalMin, rangeHigh: globalMax, isMinimalist: viewModel.useMinimalistIcons, textColor: theme.textColor)
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(TapGesture().onEnded {
                                viewModel.playHaptic(.click)
                            })
                            .id("day-\(index)")
                            
                            Divider().background(theme.textColor.opacity(0.15))
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .overlay(alignment: .topTrailing) {
                WatchDoubleTapScrollTrigger {
                    scrollToNextSection(using: proxy)
                }
            }
        }
        .focusable()
    }

    private func scrollToNextSection(using proxy: ScrollViewProxy) {
        guard scrollSectionIDs.count > 1 else { return }
        let nextIndex = doubleTapSectionIndex >= scrollSectionIDs.count - 1 ? 0 : doubleTapSectionIndex + 1
        doubleTapSectionIndex = nextIndex
        withAnimation(.easeInOut(duration: 0.28)) {
            proxy.scrollTo(scrollSectionIDs[nextIndex], anchor: .top)
        }
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
                    await viewModel.refresh()
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
                    await viewModel.refresh()
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
    @EnvironmentObject var viewModel: WatchWeatherViewModel

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "cloud")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.6))
            Text("No weather data")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.8))
            Button("Refresh") {
                Task {
                    await viewModel.refresh()
                }
            }
            .font(.caption2.weight(.semibold))
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.9))
        }
        .padding()
    }
}

struct WatchDoubleTapScrollTrigger: View {
    let action: () -> Void

    var body: some View {
        Group {
            if #available(watchOS 11.0, *) {
                Button(action: action) {
                    Color.clear
                        .frame(width: 1, height: 1)
                }
                .buttonStyle(.plain)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityHidden(true)
                .handGestureShortcut(.primaryAction)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchWeatherViewModel())
}
