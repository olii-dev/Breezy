//
//  SettingsView.swift
//  Breezy
//
//  App settings view
//

import SwiftUI
import UserNotifications

struct SettingsView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var showResetConfirmation = false
    @AppStorage("Breezy.showEditModeButton") private var showEditModeButton = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                let theme = viewModel.currentTheme(colorScheme: colorScheme)
                AnimatedGradientBackground(
                    colors: [theme.topColor, theme.bottomColor]
                )
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DesignSystem.spacingL) {
                        
                        // Main Sections
                        // Design Studio
                        VStack(spacing: DesignSystem.spacingM) {
                            SettingsNavCard(
                                title: "Design Studio",
                                icon: "paintpalette.fill",
                                color: .pink,
                                textColor: theme.textColor,
                                glassOpacity: viewModel.glassOpacity,
                                destination: DesignStudioView(viewModel: viewModel)
                            )
                            
                            SettingsNavCard(
                                title: "Widget Studio",
                                icon: "hammer.fill",
                                color: .purple,
                                textColor: theme.textColor,
                                glassOpacity: viewModel.glassOpacity,
                                destination: WidgetBuilderView(viewModel: viewModel)
                            )
                        }
                        .padding(.horizontal, DesignSystem.spacingM)
                        
                        // Main Sections
                        VStack(spacing: DesignSystem.spacingM) {
                            SettingsNavCard(
                                title: "Notifications",
                                icon: "bell.fill",
                                color: .orange,
                                textColor: theme.textColor,
                                glassOpacity: viewModel.glassOpacity,
                                destination: NotificationSettingsView(viewModel: viewModel)
                            )

                            SettingsNavCard(
                                title: "Live Activities",
                                icon: "rectangle.on.rectangle.fill",
                                color: .cyan,
                                textColor: theme.textColor,
                                glassOpacity: viewModel.glassOpacity,
                                destination: LiveActivitySettingsView(viewModel: viewModel)
                            )
                            
                            SettingsNavCard(
                                title: "Units & Data",
                                icon: "thermometer.medium",
                                color: .blue,
                                textColor: theme.textColor,
                                glassOpacity: viewModel.glassOpacity,
                                destination: DataSettingsView(viewModel: viewModel)
                            )
                            
                            // App Icon Selector removed
                        }
                        .padding(.horizontal, DesignSystem.spacingM)
                        
                        // About
                        VStack(spacing: DesignSystem.spacingM) {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(theme.textColor.opacity(0.8))
                                Text("About Breezy")
                                    .font(FontScale.headline)
                                    .foregroundColor(theme.textColor)
                                Spacer()
                            }
                            .padding(.horizontal, DesignSystem.spacingM)
                            .accessibilityAddTraits(.isHeader)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 4) {
                                    Text(Bundle.main.appVersionDisplayString)
                                        .font(FontScale.caption)
                                        .foregroundColor(theme.textColor.opacity(0.7))
                                        .contentTransition(.numericText())
                                    
                                    Image(systemName: "sparkles")
                                        .font(FontScale.caption2)
                                        .foregroundColor(theme.textColor.opacity(0.5))
                                        .symbolEffect(.pulse, options: .repeating, isActive: true)
                                }

                                NavigationLink {
                                    PrivacySupportView(
                                        weatherSource: viewModel.weatherSource,
                                        attributionURL: viewModel.attribution?.legalPageURL,
                                        textColor: theme.textColor,
                                        glassOpacity: viewModel.glassOpacity
                                    )
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "hand.raised.fill")
                                            .foregroundColor(theme.textColor.opacity(0.75))

                                        Text("Privacy & Security")
                                            .font(FontScale.subheadline.weight(.semibold))
                                            .foregroundColor(theme.textColor)

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(theme.textColor.opacity(0.45))
                                    }
                                    .padding(.vertical, 8)
                                }

                                Text("Breezy uses your location for local weather. Your saved places and settings stay private.")
                                    .font(.caption)
                                    .foregroundColor(theme.textColor.opacity(0.5))
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                                    .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
                            )
                            .padding(.horizontal, DesignSystem.spacingM)
                        }
                        
                        // Reset
                        Button {
                            HapticsManager.shared.impact(style: .medium)
                            showResetConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                .foregroundColor(.red.opacity(0.8))
                                Text("Reset to defaults")
                            }
                            .foregroundColor(.red.opacity(0.8))
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                                    .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                                            .stroke(Color.red.opacity(0.3), lineWidth: 0.5)
                                    )
                            )
                        }
                        .padding(.horizontal, DesignSystem.spacingM)
                        
                        Spacer()
                            .frame(height: 50)
                    }
                    .padding(.top, DesignSystem.spacingL)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                    }
                }
            }
            .toolbarColorScheme(viewModel.currentTheme(colorScheme: colorScheme).isDark ? .dark : .light, for: .navigationBar)
            .alert("Reset All Settings?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset Everything", role: .destructive) {
                    HapticsManager.shared.impact(style: .heavy)
                    resetDefaults()
                }
            } message: {
                Text("This will reset your units, cache settings, and clear saved locations. Widgets and watch surfaces will fall back to fresh sync after the reset. This action cannot be undone.")
            }
        }
    }
    
    private func resetDefaults() {
        viewModel.weatherSource = .weatherKit
        viewModel.radarPrecipitationSource = .rainViewer
        viewModel.temperatureUnit = .celsius
        viewModel.cacheDurationMinutes = 30
        viewModel.appearanceMode = .auto
        viewModel.useMinimalistIcons = true
        WeatherCache.clear()
        FavouritesStore.clear()
        RecentlyViewedStore.clear()
    }
}

// MARK: - Components

struct SettingsNavCard<Destination: View>: View {
    let title: String
    let icon: String
    let color: Color
    let textColor: Color
    let glassOpacity: Double
    let destination: Destination
    
    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(color)
                }
                
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundColor(textColor)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(textColor.opacity(0.5))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                    .fill(.ultraThinMaterial.opacity(glassOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                    .stroke(textColor.opacity(0.15), lineWidth: 0.5)
            )
        }
        .simultaneousGesture(TapGesture().onEnded {
            HapticsManager.shared.impact(style: .light)
        })
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

struct PrivacySupportView: View {
    let weatherSource: WeatherSource
    let attributionURL: URL?
    let textColor: Color
    let glassOpacity: Double

    @Environment(\.openURL) private var openURL

    private let weatherKitURL = URL(string: "https://developer.apple.com/weatherkit/data-source-attribution/")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.spacingL) {
                infoCard(
                    title: "Privacy",
                    systemImage: "lock.shield.fill",
                    body: "Breezy uses your location for local weather and optional alerts. Your saved places and settings stay in your own device storage and private Apple sync containers. Breezy does not use ads or analytics SDKs."
                )

                infoCard(
                    title: "Weather Data",
                    systemImage: "cloud.sun.fill",
                    body: weatherSource.privacySummary
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("Helpful Links")
                        .font(.headline)
                        .foregroundColor(textColor)

                    VStack(spacing: 0) {
                        LinkRow(title: "Privacy Policy", subtitle: "Breezy's full privacy policy on the web") {
                            openURL(URL(string: "https://olii-dev.github.io/breezy-site/privacy")!)
                        }
                        Divider()
                            .padding(.leading, 14)
                        LinkRow(title: weatherSource == .weatherKit ? "WeatherKit data sources" : "Open-Meteo docs & attribution", subtitle: weatherSource == .weatherKit ? "Apple Weather attribution and legal" : "Provider docs and usage information") {
                            openURL(attributionURL ?? weatherSource.legalURL ?? weatherKitURL)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                            .fill(.ultraThinMaterial.opacity(glassOpacity))
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Privacy & Security")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func infoCard(title: String, systemImage: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundColor(textColor)

            Text(body)
                .font(.subheadline)
                .foregroundColor(textColor.opacity(0.8))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                .fill(.ultraThinMaterial.opacity(glassOpacity))
        )
    }
}

struct LinkRow: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right.square")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .buttonStyle(.plain)
    }
}



// MARK: - General Settings

// MARK: - Data Settings

struct DataSettingsView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            let theme = viewModel.currentTheme(colorScheme: colorScheme)
            AnimatedGradientBackground(colors: [theme.topColor, theme.bottomColor])
            
            ScrollView {
                VStack(spacing: DesignSystem.spacingL) {
                    // Units Section
                    VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
                        Text("UNITS")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(theme.textColor.opacity(0.6))
                            .padding(.leading, 8)
                        
                        VStack(spacing: 0) {
                            // Temperature
                            HStack {
                                Label("Temperature", systemImage: "thermometer")
                                    .foregroundColor(theme.textColor)
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { viewModel.temperatureUnit },
                                    set: { newUnit in
                                        HapticsManager.shared.selectionChanged()
                                        viewModel.temperatureUnit = newUnit
                                        if let location = viewModel.currentLocation {
                                            Task { await viewModel.fetchWeather(for: location, isManualRefresh: false) }
                                        }
                                    }
                                )) {
                                    ForEach(TemperatureUnit.allCases) { unit in
                                        Text(unit.rawValue).tag(unit)
                                    }
                                }
                                .tint(theme.textColor)
                                .labelsHidden()
                            }
                            .padding()
                            
                            Divider().padding(.leading)
                            
                            // Wind Speed
                            HStack {
                                Label("Wind Speed", systemImage: "wind")
                                    .foregroundColor(theme.textColor)
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { viewModel.windSpeedUnit },
                                    set: { newUnit in
                                        HapticsManager.shared.selectionChanged()
                                        viewModel.windSpeedUnit = newUnit
                                        if let location = viewModel.currentLocation {
                                            Task { await viewModel.fetchWeather(for: location, isManualRefresh: false) }
                                        }
                                    }
                                )) {
                                    ForEach(WindSpeedUnit.allCases) { unit in
                                        Text(unit.displayName).tag(unit)
                                    }
                                }
                                .tint(theme.textColor)
                                .labelsHidden()
                            }
                            .padding()
                            
                            Divider().padding(.leading)
                            
                            // Pressure
                            HStack {
                                Label("Pressure", systemImage: "gauge.medium")
                                    .foregroundColor(theme.textColor)
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { viewModel.pressureUnit },
                                    set: { newUnit in
                                        HapticsManager.shared.selectionChanged()
                                        viewModel.pressureUnit = newUnit
                                        if let location = viewModel.currentLocation {
                                            Task { await viewModel.fetchWeather(for: location, isManualRefresh: false) }
                                        }
                                    }
                                )) {
                                    ForEach(PressureUnit.allCases) { unit in
                                        Text(unit.displayName).tag(unit)
                                    }
                                }
                                .tint(theme.textColor)
                                .labelsHidden()
                            }
                            .padding()
                            
                            Divider().padding(.leading)
                            
                            // Visibility
                            HStack {
                                Label("Visibility", systemImage: "eye.fill")
                                    .foregroundColor(theme.textColor)
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { viewModel.visibilityUnit },
                                    set: { newUnit in
                                        HapticsManager.shared.selectionChanged()
                                        viewModel.visibilityUnit = newUnit
                                        if let location = viewModel.currentLocation {
                                            Task { await viewModel.fetchWeather(for: location, isManualRefresh: false) }
                                        }
                                    }
                                )) {
                                    ForEach(VisibilityUnit.allCases) { unit in
                                        Text(unit.rawValue).tag(unit)
                                    }
                                }
                                .tint(theme.textColor)
                                .labelsHidden()
                            }
                            .padding()
                            
                            Divider().padding(.leading)
                            
                            // Precipitation
                            HStack {
                                Label("Precipitation", systemImage: "cloud.rain.fill")
                                    .foregroundColor(theme.textColor)
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { viewModel.precipitationUnit },
                                    set: { newUnit in
                                        HapticsManager.shared.selectionChanged()
                                        viewModel.precipitationUnit = newUnit
                                        if let location = viewModel.currentLocation {
                                            Task { await viewModel.fetchWeather(for: location, isManualRefresh: false) }
                                        }
                                    }
                                )) {
                                    ForEach(PrecipitationUnit.allCases) { unit in
                                        Text(unit.rawValue).tag(unit)
                                    }
                                }
                                .tint(theme.textColor)
                                .labelsHidden()
                            }
                            .padding()
                            
                            Divider().padding(.leading)
                            
                            // Date Format
                            VStack(spacing: 6) {
                                HStack {
                                    Label("Date Format", systemImage: "calendar")
                                        .foregroundColor(theme.textColor)
                                    Spacer()
                                    // Menu shows just the name; the live example
                                    // sits below so the row never wraps.
                                    Picker("Date Format", selection: $viewModel.dateFormat) {
                                        ForEach(DateFormat.allCases) { format in
                                            Text(format.rawValue).tag(format)
                                        }
                                    }
                                    .tint(theme.textColor)
                                    .labelsHidden()
                                    .onChange(of: viewModel.dateFormat) { _, _ in
                                        HapticsManager.shared.selectionChanged()
                                    }
                                }
                                Text("Example: \(viewModel.dateFormat.example)")
                                    .font(.caption)
                                    .foregroundColor(theme.textColor.opacity(0.55))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
                    }

                    VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
                        Text("WEATHER SOURCE")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(theme.textColor.opacity(0.6))
                            .padding(.leading, 8)

                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Weather Source", selection: Binding(
                                get: { viewModel.weatherSource },
                                set: { newSource in
                                    HapticsManager.shared.selectionChanged()
                                    let previousSource = viewModel.weatherSource
                                    guard previousSource != newSource else { return }
                                    let preferredLocation = viewModel.preferredLocationForCurrentSelection()
                                    viewModel.weatherSource = newSource
                                    viewModel.weather = nil
                                    viewModel.currentLocation = preferredLocation
                                    viewModel.loadCacheIfValid(expectedLocation: preferredLocation)
                                    if viewModel.weather == nil, let location = preferredLocation {
                                        Task { await viewModel.fetchWeather(for: location, isManualRefresh: false) }
                                    }
                                }
                            )) {
                                ForEach(WeatherSource.allCases) { source in
                                    Text(source.shortLabel).tag(source)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text(viewModel.weatherSource.privacySummary)
                                .font(.caption)
                                .foregroundColor(theme.textColor.opacity(0.6))

                            Text(viewModel.providerCapabilities.historicalAvailabilityDescription)
                                .font(.caption2)
                                .foregroundColor(theme.textColor.opacity(0.45))
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
                    }

                    VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
                        Text("RADAR")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(theme.textColor.opacity(0.6))
                            .padding(.leading, 8)

                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Precipitation Radar Source", selection: Binding(
                                get: { viewModel.radarPrecipitationSource },
                                set: { newSource in
                                    HapticsManager.shared.selectionChanged()
                                    viewModel.radarPrecipitationSource = newSource
                                }
                            )) {
                                ForEach(RadarPrecipitationSource.allCases) { source in
                                    Text(source.displayName).tag(source)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text(viewModel.radarPrecipitationSource.subtitle)
                                .font(.caption)
                                .foregroundColor(theme.textColor.opacity(0.6))

                            Text("This affects the precipitation layer only. Wind, clouds, temperature, and pressure continue using Breezy's existing weather map tiles.")
                                .font(.caption2)
                                .foregroundColor(theme.textColor.opacity(0.45))
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
                    }
                    
                    // Cache Section
                    VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
                        Text("CACHE")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(theme.textColor.opacity(0.6))
                            .padding(.leading, 8)
                        
                        VStack(spacing: DesignSystem.spacingS) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Label("Duration", systemImage: "clock.arrow.circlepath")
                                        .foregroundColor(theme.textColor)
                                    Spacer()
                                    Stepper("\(viewModel.cacheDurationMinutes) min", value: $viewModel.cacheDurationMinutes, in: 1...1440)
                                        .foregroundColor(theme.textColor)
                                }
                                
                                Text("Between 1 min and 24 hours")
                                    .font(FontScale.caption2)
                                    .foregroundColor(theme.textColor.opacity(0.5))
                            }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
                            
                            Button {
                                WeatherCache.clear()
                                viewModel.weather = nil
                            } label: {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Clear Cache")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
                                .foregroundColor(.red.opacity(0.8))
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Units & Data")
    }
}




// MARK: - Notification Settings

struct NotificationSettingsView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    
    @State private var notificationSettings = UserDefaults.standard.notificationSettings
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showResetConfirmation = false
    @State private var previousWindUnit: WindSpeedUnit?
    @State private var previousTempUnit: TemperatureUnit?
    
    init(viewModel: WeatherViewModel) {
        self.viewModel = viewModel
        _notificationSettings = State(initialValue: UserDefaults.standard.notificationSettings)
    }
    
    var body: some View {
        ZStack {
            let theme = viewModel.currentTheme(colorScheme: colorScheme)
            AnimatedGradientBackground(colors: [theme.topColor, theme.bottomColor])
            
            ScrollView {
                VStack(spacing: DesignSystem.spacingL) {
                    
                    // Permission Status
                    HStack {
                        Image(systemName: notificationStatus == .authorized ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(statusColor)
                        Text("Notifications: \(statusText)")
                            .foregroundColor(theme.textColor)
                        Spacer()
                        if notificationStatus != .authorized {
                            Button("Enable") {
                                Task {
                                    await enableNotifications()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
                    
                    
                    // Weather Alerts — each alert customizes on its own page
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ALERTS")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(theme.textColor.opacity(0.6))
                            .padding(.leading, 8)

                        VStack(spacing: DesignSystem.spacingS) {
                            alertRow(
                                "Daily Forecast", icon: "sunrise.fill", color: .orange, theme: theme,
                                isOn: notificationSettings.dailyForecastEnabled,
                                set: { notificationSettings.dailyForecastEnabled = $0 },
                                config: AlertDetailSettingsView.AlertDetailConfig(
                                    title: "Daily Forecast", icon: "sunrise.fill", color: .orange,
                                    soundPath: \NotificationSettings.dailyForecastSound,
                                    content: .daily,
                                    isDailyForecast: true
                                )
                            )

                            alertRow(
                                "Severe Weather", icon: "exclamationmark.triangle.fill", color: .red, theme: theme,
                                isOn: notificationSettings.severeWeatherEnabled,
                                set: { notificationSettings.severeWeatherEnabled = $0 },
                                config: AlertDetailSettingsView.AlertDetailConfig(
                                    title: "Severe Weather", icon: "exclamationmark.triangle.fill", color: .red,
                                    threshold: nil,
                                    cooldown: .severe,
                                    soundPath: \NotificationSettings.severeWeatherSound,
                                    content: .severe
                                )
                            )

                            alertRow(
                                "Rain Alerts", icon: "cloud.rain.fill", color: .blue, theme: theme,
                                isOn: notificationSettings.rainAlertsEnabled,
                                set: { notificationSettings.rainAlertsEnabled = $0 },
                                config: AlertDetailSettingsView.AlertDetailConfig(
                                    title: "Rain Alerts", icon: "cloud.rain.fill", color: .blue,
                                    threshold: .rainChance,
                                    cooldown: .rain,
                                    soundPath: \NotificationSettings.rainAlertSound,
                                    content: .alerts
                                )
                            )

                            alertRow(
                                "UV Alerts", icon: "sun.max.fill", color: .yellow, theme: theme,
                                isOn: notificationSettings.uvAlertsEnabled,
                                set: { notificationSettings.uvAlertsEnabled = $0 },
                                config: AlertDetailSettingsView.AlertDetailConfig(
                                    title: "UV Alerts", icon: "sun.max.fill", color: .yellow,
                                    threshold: .uv,
                                    cooldown: .uv,
                                    soundPath: \NotificationSettings.uvAlertSound,
                                    content: .alerts
                                )
                            )

                            alertRow(
                                "Temperature Changes", icon: "thermometer.variable", color: .orange, theme: theme,
                                isOn: notificationSettings.temperatureChangeAlertsEnabled,
                                set: { notificationSettings.temperatureChangeAlertsEnabled = $0 },
                                config: AlertDetailSettingsView.AlertDetailConfig(
                                    title: "Temperature Changes", icon: "thermometer.variable", color: .orange,
                                    threshold: .temperatureChange,
                                    soundPath: \NotificationSettings.temperatureChangeSound,
                                    content: .alerts
                                )
                            )

                            alertRow(
                                "High Wind", icon: "wind", color: .cyan, theme: theme,
                                isOn: notificationSettings.windAlertsEnabled,
                                set: { notificationSettings.windAlertsEnabled = $0 },
                                config: AlertDetailSettingsView.AlertDetailConfig(
                                    title: "High Wind", icon: "wind", color: .cyan,
                                    threshold: .windSpeed,
                                    cooldown: .wind,
                                    soundPath: \NotificationSettings.windAlertSound,
                                    content: .alerts
                                )
                            )

                            alertRow(
                                "Rain Probability", icon: "cloud.drizzle.fill", color: .teal, theme: theme,
                                isOn: notificationSettings.precipitationProbabilityAlertsEnabled,
                                set: { notificationSettings.precipitationProbabilityAlertsEnabled = $0 },
                                config: AlertDetailSettingsView.AlertDetailConfig(
                                    title: "Rain Probability", icon: "cloud.drizzle.fill", color: .teal,
                                    threshold: .rainProbability,
                                    soundPath: \NotificationSettings.precipitationProbabilitySound,
                                    content: .alerts
                                )
                            )
                        }
                    }

                    // Quiet Hours (severe weather alerts ignore these for safety)
                    VStack(spacing: DesignSystem.spacingS) {
                        SettingsToggleRow(title: "Enable Quiet Hours", icon: "moon.fill", color: .indigo, textColor: theme.textColor, isOn: Binding(get: {notificationSettings.quietHoursEnabled}, set: {notificationSettings.quietHoursEnabled=$0; saveNotificationSettings()}))

                        if notificationSettings.quietHoursEnabled {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Start")
                                        .foregroundColor(theme.textColor.opacity(0.7))
                                    Spacer()
                                    Picker("", selection: Binding(get: {notificationSettings.quietHoursStart}, set: {notificationSettings.quietHoursStart=$0; saveNotificationSettings()})) {
                                        ForEach(0..<24, id: \.self) { hour in
                                            Text(String(format: "%02d:00", hour)).tag(hour)
                                        }
                                    }
                                    .tint(theme.textColor)
                                }

                                HStack {
                                    Text("End")
                                        .foregroundColor(theme.textColor.opacity(0.7))
                                    Spacer()
                                    Picker("", selection: Binding(get: {notificationSettings.quietHoursEnd}, set: {notificationSettings.quietHoursEnd=$0; saveNotificationSettings()})) {
                                        ForEach(0..<24, id: \.self) { hour in
                                            Text(String(format: "%02d:00", hour)).tag(hour)
                                        }
                                    }
                                    .tint(theme.textColor)
                                }

                                Text("Severe weather alerts ignore quiet hours for safety")
                                    .font(.caption2)
                                    .foregroundColor(theme.textColor.opacity(0.5))
                            }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
                        }
                    }

                    // Reset thresholds
                    Button {
                        showResetConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                                .foregroundColor(.orange)
                            Text("Reset All Thresholds to Defaults")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(theme.textColor)
                            Spacer()
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.orange.opacity(0.2)))
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Notifications")
        .onAppear {
            Task { await checkNotificationStatus() }
            // Store initial units for conversion detection
            previousWindUnit = viewModel.windSpeedUnit
            previousTempUnit = viewModel.temperatureUnit
        }
        .onChange(of: viewModel.windSpeedUnit) { _, newUnit in
            guard let oldUnit = previousWindUnit, oldUnit != newUnit else {
                previousWindUnit = newUnit
                return
            }
            
            // Convert threshold via m/s so all WindSpeedUnit cases stay coherent
            let currentThreshold = Double(notificationSettings.windSpeedThreshold)
            let metersPerSecond = Self.windThresholdToMetersPerSecond(currentThreshold, unit: oldUnit)
            let convertedThreshold = Int(round(Self.windThresholdFromMetersPerSecond(metersPerSecond, unit: newUnit)))
            
            notificationSettings.windSpeedThreshold = max(1, convertedThreshold)
            saveNotificationSettings()
            previousWindUnit = newUnit
        }
        .onChange(of: viewModel.temperatureUnit) { _, newUnit in
            guard let oldUnit = previousTempUnit, oldUnit != newUnit else {
                previousTempUnit = newUnit
                return
            }
            
            // Convert temperature change threshold
            let currentThreshold = Double(notificationSettings.temperatureChangeThreshold)
            let convertedThreshold: Int
            
            if newUnit == .fahrenheit {
                // C to F
                convertedThreshold = Int(round(currentThreshold * 1.8))
            } else {
                // F to C
                convertedThreshold = Int(round(currentThreshold / 1.8))
            }
            
            notificationSettings.temperatureChangeThreshold = convertedThreshold
            saveNotificationSettings()
            previousTempUnit = newUnit
        }
        .alert("Reset Thresholds", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                notificationSettings.resetThresholdsToDefaults()
                saveNotificationSettings()
            }
        } message: {
            Text("This will reset all notification thresholds to their default values. Your other notification preferences will not be affected.")
        }
    }

    private var statusText: String {
        switch notificationStatus {
        case .authorized: return "Enabled"
        case .denied: return "Denied"
        default: return "Not Set"
        }
    }
    
    private var statusColor: Color {
        notificationStatus == .authorized ? .green : .orange
    }
    
    private func checkNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
    }

    private func enableNotifications() async {
        let granted = await NotificationManager.shared.requestAuthorization()
        await checkNotificationStatus()

        guard granted || notificationStatus == .authorized else { return }

        NotificationManager.shared.registerNotificationCategories()
        saveNotificationSettings()
    }
    
    private func saveNotificationSettings() {
        UserDefaults.standard.notificationSettings = notificationSettings
        NotificationManager.shared.updateSettings(notificationSettings, weather: viewModel.weather, temperatureUnit: viewModel.temperatureUnit)
    }

    /// Alert list row: inline toggle + full customization one tap deeper.
    private func alertRow(
        _ title: String,
        icon: String,
        color: Color,
        theme: WeatherTheme,
        isOn: Bool,
        set: @escaping (Bool) -> Void,
        config: AlertDetailSettingsView.AlertDetailConfig
    ) -> some View {
        NavigationLink {
            AlertDetailSettingsView(
                settings: $notificationSettings,
                viewModel: viewModel,
                config: config,
                onSave: { saveNotificationSettings() }
            )
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                    .frame(width: 26)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(theme.textColor)

                Spacer(minLength: 0)

                Toggle("", isOn: Binding(
                    get: { isOn },
                    set: { set($0); saveNotificationSettings() }
                ))
                .labelsHidden()
                .tint(color)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(theme.textColor.opacity(0.4))
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
        }
        .buttonStyle(.plain)
    }

    private static func windThresholdToMetersPerSecond(_ value: Double, unit: WindSpeedUnit) -> Double {
        switch unit {
        case .metersPerSecond: return value
        case .kilometersPerHour: return value / 3.6
        case .milesPerHour: return value / 2.23694
        case .knots: return value / 1.94384
        }
    }

    private static func windThresholdFromMetersPerSecond(_ metersPerSecond: Double, unit: WindSpeedUnit) -> Double {
        unit.convert(metersPerSecond)
    }
}

// MARK: - Location Settings

struct LocationSettingsView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            let theme = viewModel.currentTheme(colorScheme: colorScheme)
            AnimatedGradientBackground(colors: [theme.topColor, theme.bottomColor])
            
            ScrollView {
                VStack(spacing: DesignSystem.spacingL) {
                    
                    VStack(spacing: DesignSystem.spacingS) {
                        Button {
                            Task {
                                do {
                                    let loc = try await LocationHelper().requestLocationAndGetData()
                                    await viewModel.fetchWeather(for: loc)
                                } catch {}
                            }
                        } label: {
                            HStack {
                                Image(systemName: "location.fill")
                                Text("Request Location Now")
                            }
                            .foregroundColor(theme.textColor)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
                        }
}

                    // Favourites
                    VStack(alignment: .leading, spacing: DesignSystem.spacingM) {
                        Text("FAVOURITES")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(theme.textColor.opacity(0.6))
                            .padding(.leading, 8)
                        
                        if FavouritesStore.favourites.isEmpty {
                            Text("No favourites yet")
                                .foregroundColor(theme.textColor.opacity(0.5))
                                .padding()
                        } else {
                            ForEach(FavouritesStore.favourites, id: \.city) { location in
                                HStack {
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundColor(theme.textColor)
                                    Text(location.city).foregroundColor(theme.textColor)
                                    Spacer()
                                    Button {
                                        FavouritesStore.remove(location)
                                    } label: {
                                        Image(systemName: "trash").foregroundColor(.red.opacity(0.8))
                                    }
                                }
                                .padding()
                                .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
                            }
                            
                            Button("Clear All") { FavouritesStore.clear() }
                                .foregroundColor(.red.opacity(0.8))
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Locations")
    }
}

// MARK: - Design Studio Unified Hub

struct DesignStudioView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("Breezy.showEditModeButton") private var showEditModeButton = true

    private var navigationRefreshID: String {
        let theme = viewModel.currentTheme(colorScheme: colorScheme)
        return "design-studio-\(viewModel.appearanceMode.rawValue)-\(theme.isDark)-\(theme.textColor.description)"
    }
    
    var body: some View {
        ZStack {
            let theme = viewModel.currentTheme(colorScheme: colorScheme)
            AnimatedGradientBackground(colors: [theme.topColor, theme.bottomColor])
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: DesignSystem.spacingXL) {
                    VStack(alignment: .leading, spacing: 6) {

                        Text("Fine tune Breezy's look, typography, and dashboard.")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(theme.textColor.opacity(0.62))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    
                    // 1. Style Section (Theme & Icons)
                    VStack(alignment: .leading, spacing: DesignSystem.spacingM) {
                        StudioHeader(title: "STYLE", icon: "paintbrush.fill", theme: theme)
                        
                        VStack(spacing: DesignSystem.spacingS) {
                            HStack {
                                Text("Appearance")
                                    .foregroundColor(theme.textColor)
                                Spacer()
                                Picker("", selection: $viewModel.appearanceMode) {
                                    ForEach(AppearanceMode.allCases) { mode in
                                        Text(mode.rawValue).tag(mode)
                                    }
                                }
                                .tint(theme.textColor)
                            }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
                            
                            // Themes Navigation
                            NavigationLink {
                                ThemeGalleryView(viewModel: viewModel)
                            } label: {
                                HStack {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                            .frame(width: 32, height: 32)
                                        Image(systemName: "swatchpalette.fill")
                                            .foregroundColor(.white)
                                            .font(.system(size: 16))
                                    }
                                    
                                    Text("Themes")
                                        .foregroundColor(theme.textColor)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(theme.textColor.opacity(0.5))
                                }
                                .padding()
                                .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
                            }

                            SettingsToggleRow(
                                title: "Emojis",
                                icon: "face.smiling",
                                color: .yellow,
                                textColor: theme.textColor,
                                isOn: Binding(
                                    get: { !viewModel.useMinimalistIcons },
                                    set: { viewModel.useMinimalistIcons = !$0 }
                                )
                            )
                            
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "square.stack.3d.forward.dottedline.fill")
                                        .foregroundColor(.blue)
                                    Text("Material Opacity")
                                        .foregroundColor(theme.textColor)
                                    Spacer()
                                    Text("\(Int(viewModel.glassOpacity * 100))%")
                                        .font(.caption.monospacedDigit())
                                        .foregroundColor(theme.textColor.opacity(0.6))
                                }
                                
                                Slider(value: $viewModel.glassOpacity, in: 0.0...1.0, step: 0.01)
                                    .tint(theme.textColor)

                                HStack {
                                    Spacer()
                                    Button("Reset") {
                                        viewModel.glassOpacity = 0.35
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(DesignSystem.skyBlue)
                                }
                            }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
                            
                            SettingsToggleRow(
                                title: "Edit Button",
                                icon: "pencil.circle",
                                color: .indigo,
                                textColor: theme.textColor,
                                isOn: $showEditModeButton
                            )
                            
                            // App Icons Gallery Navigation
                            #if !targetEnvironment(macCatalyst)
                            NavigationLink {
                                IconGalleryView(viewModel: viewModel)
                            } label: {
                                HStack {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(LinearGradient(colors: [Color.purple, Color.pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                                            .frame(width: 32, height: 32)
                                        Image(systemName: "app.fill")
                                            .foregroundColor(.white)
                                            .font(.system(size: 16))
                                    }

                                    Text("App Icons")
                                        .foregroundColor(theme.textColor)

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(theme.textColor.opacity(0.5))
                                }
                                .padding()
                                .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
                            }
                            #endif
                        }
                    }
                    
                    // 2. Typography Section
                    VStack(alignment: .leading, spacing: DesignSystem.spacingM) {
                        StudioHeader(title: "TYPOGRAPHY", icon: "textformat", theme: theme)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DesignSystem.spacingS) {
                                ForEach(WeatherFont.allCases) { font in
                                    Button {
                                        withAnimation { viewModel.typography = font }
                                    } label: {
                                        VStack(spacing: 8) {
                                            Text("Aa")
                                                .font(.system(size: 32, weight: .bold))
                                                .fontDesign(font.design)
                                            Text(font.rawValue)
                                                .font(.caption.weight(.medium))
                                        }
                                        .foregroundColor(theme.textColor)
                                        .frame(width: 90, height: 90)
                                        .background(
                                            RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                                                .fill(
                                                    .ultraThinMaterial.opacity(
                                                        viewModel.typography == font
                                                            ? min(1.0, viewModel.glassOpacity + 0.25)
                                                            : max(0.08, viewModel.glassOpacity * 0.75)
                                                    )
                                                )
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                                                .stroke(viewModel.typography == font ? Color.blue : Color.clear, lineWidth: 2)
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    }
                    
                    VStack(alignment: .leading, spacing: DesignSystem.spacingM) {
                        StudioHeader(title: "DAILY VIEW", icon: "sun.max.trianglebadge.exclamationmark", theme: theme)

                        NavigationLink {
                            DayDetailSettingsView(viewModel: viewModel)
                        } label: {
                            HStack(spacing: 16) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(LinearGradient(colors: [Color.orange, Color.yellow], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 36, height: 36)

                                    Image(systemName: "slider.horizontal.3")
                                        .foregroundColor(.white)
                                        .font(.system(size: 16, weight: .semibold))
                                }	

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Daily View")
                                        .foregroundColor(theme.textColor)
                                    Text("Choose which sections appear when you open a day in the 10 day forecast.")
                                        .font(.caption)
                                        .foregroundColor(theme.textColor.opacity(0.62))
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(theme.textColor.opacity(0.5))
                            }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
                        }
                    }

                    // 3. Dashboard Info
                    VStack(alignment: .leading, spacing: DesignSystem.spacingM) {
                        StudioHeader(title: "WIDGET LAYOUT", icon: "square.grid.2x2.fill", theme: theme)
                        
                        VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
                            HStack(spacing: 16) {
                                Image(systemName: "hand.tap.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Manage your dashboard layout directly on the home screen.")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(theme.textColor)
                                    Text("Long press any widget to enter Edit Mode (or hold down on blank space), then drag to reorder or tap (+) to add new widgets.")
                                        .font(.caption)
                                        .foregroundColor(theme.textColor.opacity(0.6))
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
                        }
                    }
                    
                }
                .padding(DesignSystem.spacingM)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .id(navigationRefreshID)
        .navigationTitle("Design Studio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Design Studio")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
            }
        }
        .toolbarColorScheme(viewModel.currentTheme(colorScheme: colorScheme).isDark ? .dark : .light, for: .navigationBar)
    }
}

struct InfoButton: View {
    let color: Color
    let title: String
    let description: String
    
    @State private var showingInfo = false
    
    var body: some View {
        Button {
            showingInfo = true
        } label: {
            Image(systemName: "info.circle")
                .font(FontScale.caption2)
                .foregroundColor(color.opacity(0.7))
        }
        .buttonStyle(.plain)
        .alert(title, isPresented: $showingInfo) {
            Button("Got it", role: .cancel) { }
        } message: {
            Text(description)
        }
    }
}

struct AddForecastTimeView: View {
    @Binding var settings: NotificationSettings
    @State private var selectedHour = 8
    @State private var selectedMinute = 0
    var onAdd: (ForecastTime) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section("Select Time") {
                    Picker("Hour", selection: $selectedHour) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text("\(hour)").tag(hour)
                        }
                    }
                    Picker("Minute", selection: $selectedMinute) {
                        ForEach([0, 15, 30, 45], id: \.self) { minute in
                            Text(String(format: "%02d", minute)).tag(minute)
                        }
                    }
                }
            }
            .navigationTitle("Add Forecast Time")
            .navigationBarItems(
                leading: Button("Cancel") { onAdd(ForecastTime(hour: -1, minute: 0)) },
                trailing: Button("Add") {
                    onAdd(ForecastTime(hour: selectedHour, minute: selectedMinute))
                }
            )
        }
    }
}
