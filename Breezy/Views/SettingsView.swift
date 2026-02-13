//
//  SettingsView.swift
//  Breezy
//
//  App settings view
//

import SwiftUI
import UserNotifications
import WeatherKit

struct SettingsView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var showResetConfirmation = false
    
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
                                destination: DesignStudioView(viewModel: viewModel)
                            )
                            
                            SettingsNavCard(
                                title: "Widget Studio",
                                icon: "hammer.fill",
                                color: .purple,
                                textColor: theme.textColor,
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
                                destination: NotificationSettingsView(viewModel: viewModel)
                            )
                            
                            SettingsNavCard(
                                title: "Units & Data",
                                icon: "thermometer.medium",
                                color: .blue,
                                textColor: theme.textColor,
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
                                    .font(.headline)
                                    .foregroundColor(theme.textColor)
                                Spacer()
                            }
                            .padding(.horizontal, DesignSystem.spacingM)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Version 0.1")
                                    .font(.caption)
                                    .foregroundColor(theme.textColor.opacity(0.7))
                                
                                if let attribution = viewModel.attribution {
                                    VStack(alignment: .leading, spacing: 4) {
                                        AsyncImage(url: attribution.combinedMarkDarkURL) { image in
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(height: 12)
                                        } placeholder: {
                                            ProgressView()
                                                .scaleEffect(0.5)
                                        }
                                        
                                        Link("Data Sources", destination: attribution.legalPageURL)
                                            .font(.caption2)
                                            .foregroundColor(theme.textColor.opacity(0.8))
                                            .underline()
                                    }
                                } else {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Weather data provided by Apple Weather")
                                            .font(.caption2)
                                            .foregroundColor(theme.textColor.opacity(0.5))
                                        
                                        Link("Data sources and legal", destination: URL(string: "https://developer.apple.com/weatherkit/data-source-attribution/")!)
                                            .font(.caption2)
                                            .foregroundColor(theme.textColor.opacity(0.8))
                                            .underline()
                                    }
                                }
                                
                                Text("No data is sent to third parties by this app. Your data is secure and will never be shared.")
                                    .font(.caption)
                                    .foregroundColor(theme.textColor.opacity(0.5))
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                                    .fill(.ultraThinMaterial.opacity(0.3))
                            )
                            .padding(.horizontal, DesignSystem.spacingM)
                        }
                        
                        // Reset
                        Button {
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
                                    .fill(.ultraThinMaterial.opacity(0.2))
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
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                            .font(.title3)
                    }
                }
            }
            .toolbarColorScheme(viewModel.currentTheme(colorScheme: colorScheme).isDark ? .dark : .light, for: .navigationBar)
            .alert("Reset All Settings?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset Everything", role: .destructive) {
                    resetDefaults()
                }
            } message: {
                Text("This will reset your units, cache settings, and clear all saved locations. This action cannot be undone.")
            }
        }
    }
    
    private func resetDefaults() {
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
                    .fill(.ultraThinMaterial.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                    .stroke(textColor.opacity(0.15), lineWidth: 0.5)
            )
        }
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
                                Picker("", selection: $viewModel.windSpeedUnit) {
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
                                Picker("", selection: $viewModel.pressureUnit) {
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
                                Picker("", selection: $viewModel.visibilityUnit) {
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
                                Picker("", selection: $viewModel.precipitationUnit) {
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
                            HStack {
                                Label("Date Format", systemImage: "calendar")
                                    .foregroundColor(theme.textColor)
                                Spacer()
                                Picker("", selection: $viewModel.dateFormat) {
                                    ForEach(DateFormat.allCases) { format in
                                        Text("\(format.rawValue) (\(format.example))").tag(format)
                                    }
                                }
                                .tint(theme.textColor)
                                .labelsHidden()
                            }
                            .padding()
                        }
                        .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(0.4)))
                    }
                    
                    // Cache Section
                    VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
                        Text("CACHE")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(theme.textColor.opacity(0.6))
                            .padding(.leading, 8)
                        
                        VStack(spacing: DesignSystem.spacingS) {
                            HStack {
                                Label("Duration", systemImage: "clock.arrow.circlepath")
                                    .foregroundColor(theme.textColor)
                                Spacer()
                                Stepper("\(viewModel.cacheDurationMinutes) min", value: $viewModel.cacheDurationMinutes, in: 1...1440)
                                    .foregroundColor(theme.textColor)
                            }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(0.4)))
                            
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
                                .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(0.4)))
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
    @State private var essentialAlertsExpanded = true
    @State private var weatherAlertsExpanded = false
    @State private var advancedExpanded = false
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
                                    _ = await NotificationManager.shared.requestAuthorization()
                                    await checkNotificationStatus()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(0.3)))
                    
                    
                    // Essential Alerts Section
                    DisclosureGroup(isExpanded: $essentialAlertsExpanded) {
                        VStack(spacing: DesignSystem.spacingS) {
                            SettingsToggleRow(title: "Daily Forecast", icon: "sunrise.fill", color: .orange, textColor: theme.textColor, isOn: Binding(get: {notificationSettings.dailyForecastEnabled}, set: {notificationSettings.dailyForecastEnabled=$0; saveNotificationSettings()}))
                            
                            if notificationSettings.dailyForecastEnabled {
                                DatePicker("Forecast Time", selection: Binding(
                                    get: {
                                        let c = Calendar.current
                                        var comps = DateComponents()
                                        comps.hour = notificationSettings.dailyForecastHour
                                        comps.minute = notificationSettings.dailyForecastMinute
                                        return c.date(from: comps) ?? Date()
                                    },
                                    set: {
                                        let c = Calendar.current
                                        notificationSettings.dailyForecastHour = c.component(.hour, from: $0)
                                        notificationSettings.dailyForecastMinute = c.component(.minute, from: $0)
                                        saveNotificationSettings()
                                    }
                                ), displayedComponents: .hourAndMinute)
                                .padding()
                                .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(0.3)))
                            }
                            
                            SettingsToggleRow(title: "Severe Weather", icon: "exclamationmark.triangle.fill", color: .red, textColor: theme.textColor, isOn: Binding(get: {notificationSettings.severeWeatherEnabled}, set: {notificationSettings.severeWeatherEnabled=$0; saveNotificationSettings()}))
                            
                            SettingsToggleRow(title: "UV Alerts", icon: "sun.max.fill", color: .yellow, textColor: theme.textColor, isOn: Binding(get: {notificationSettings.uvAlertsEnabled}, set: {notificationSettings.uvAlertsEnabled=$0; saveNotificationSettings()}))
                        }
                    } label: {
                        HStack {
                            Image(systemName: "bell.badge.fill")
                                .foregroundColor(.orange)
                            Text("Essential Alerts")
                                .font(.headline)
                                .foregroundColor(theme.textColor)
                        }
                    }
                    .tint(theme.textColor)
                    
                    // All Other Alerts Section
                    DisclosureGroup(isExpanded: $weatherAlertsExpanded) {
                        VStack(spacing: DesignSystem.spacingS) {
                            SettingsToggleRow(title: "Rain Alerts", icon: "cloud.rain.fill", color: .blue, textColor: theme.textColor, isOn: Binding(get: {notificationSettings.rainAlertsEnabled}, set: {notificationSettings.rainAlertsEnabled=$0; saveNotificationSettings()}))
                            
                            SettingsToggleRow(title: "Rain Probability", icon: "cloud.drizzle.fill", color: .teal, textColor: theme.textColor, isOn: Binding(get: {notificationSettings.precipitationProbabilityAlertsEnabled}, set: {notificationSettings.precipitationProbabilityAlertsEnabled=$0; saveNotificationSettings()}))
                            
                            SettingsToggleRow(title: "Temperature Changes", icon: "thermometer.variable", color: .orange, textColor: theme.textColor, isOn: Binding(get: {notificationSettings.temperatureChangeAlertsEnabled}, set: {notificationSettings.temperatureChangeAlertsEnabled=$0; saveNotificationSettings()}))
                            
                            SettingsToggleRow(title: "High Wind", icon: "wind", color: .cyan, textColor: theme.textColor, isOn: Binding(get: {notificationSettings.windAlertsEnabled}, set: {notificationSettings.windAlertsEnabled=$0; saveNotificationSettings()}))
                        }
                    } label: {
                        HStack {
                            Image(systemName: "cloud.rain.fill")
                                .foregroundColor(.blue)
                            Text("Other Weather Alerts")
                                .font(.headline)
                                .foregroundColor(theme.textColor)
                        }
                    }
                    .tint(theme.textColor)
                    
                    
                    // Advanced Settings, Quiet Hours & Preferences
                    DisclosureGroup(isExpanded: $advancedExpanded) {
                        VStack(alignment: .leading, spacing: 16) {
                            // Quiet Hours
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
                                    .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(0.3)))
                                }
                            }
                            
                            Divider()
                            
                            // Preferences
                            SettingsToggleRow(title: "Critical Sound for Severe Weather", icon: "speaker.wave.3.fill", color: .red, textColor: theme.textColor, isOn: Binding(get: {notificationSettings.useCriticalAlertsForSevere}, set: {notificationSettings.useCriticalAlertsForSevere=$0; saveNotificationSettings()}))
                            
                            SettingsToggleRow(title: "Weekdays Only Daily Forecast", icon: "calendar", color: .purple, textColor: theme.textColor, isOn: Binding(get: {notificationSettings.onlyWeekdayForecast}, set: {notificationSettings.onlyWeekdayForecast=$0; saveNotificationSettings()}))
                            
                            Divider()
                            // UV Threshold
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("UV Threshold", systemImage: "sun.max.fill")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(theme.textColor)
                                    Spacer()
                                    Text("\(notificationSettings.uvThreshold)+")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.yellow)
                                }
                                
                                Slider(value: Binding(
                                    get: { Double(notificationSettings.uvThreshold) },
                                    set: { notificationSettings.uvThreshold = Int($0); saveNotificationSettings() }
                                ), in: 3...11, step: 1)
                                .tint(.yellow)
                                
                                Text("Alert when UV index reaches this level")
                                    .font(.caption2)
                                    .foregroundColor(theme.textColor.opacity(0.5))
                            }
                            
                            Divider()
                            
                            // UV Cooldown
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("UV Alert Cooldown", systemImage: "clock.fill")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(theme.textColor)
                                    Spacer()
                                    Text("\(notificationSettings.uvAlertCooldownMinutes / 60)h")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.yellow)
                                }
                                
                                Slider(value: Binding(
                                    get: { Double(notificationSettings.uvAlertCooldownMinutes) },
                                    set: { notificationSettings.uvAlertCooldownMinutes = Int($0); saveNotificationSettings() }
                                ), in: 60...360, step: 60)
                                .tint(.yellow)
                                
                                Text("Minimum time between UV alerts for same location")
                                    .font(.caption2)
                                    .foregroundColor(theme.textColor.opacity(0.5))
                            }
                            
                            Divider()
                            
                            // Rain Cooldown
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("Rain Alert Cooldown", systemImage: "clock.fill")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(theme.textColor)
                                    Spacer()
                                    Text("\(notificationSettings.rainAlertCooldownMinutes)m")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.blue)
                                }
                                
                                Slider(value: Binding(
                                    get: { Double(notificationSettings.rainAlertCooldownMinutes) },
                                    set: { notificationSettings.rainAlertCooldownMinutes = Int($0); saveNotificationSettings() }
                                ), in: 5...60, step: 5)
                                .tint(.blue)
                                
                                Text("Minimum time between rain alerts")
                                    .font(.caption2)
                                    .foregroundColor(theme.textColor.opacity(0.5))
                            }
                            
                            Divider()
                            
                            // Temperature Change Threshold
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("Temperature Change", systemImage: "thermometer.variable")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(theme.textColor)
                                    Spacer()
                                    Text("\(notificationSettings.temperatureChangeThreshold)°")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.orange)
                                }
                                
                                Slider(value: Binding(
                                    get: { Double(notificationSettings.temperatureChangeThreshold) },
                                    set: { notificationSettings.temperatureChangeThreshold = Int($0); saveNotificationSettings() }
                                ), in: 5...20, step: 1)
                                .tint(.orange)
                                
                                Text("Alert when temperature changes by this amount from yesterday")
                                    .font(.caption2)
                                    .foregroundColor(theme.textColor.opacity(0.5))
                            }
                            
                            Divider()
                            
                            // Wind Speed Threshold
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("Wind Speed Alert", systemImage: "wind")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(theme.textColor)
                                    Spacer()
                                    Text("\(notificationSettings.windSpeedThreshold) \(viewModel.windSpeedUnit == .milesPerHour ? "mph" : "km/h")")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.cyan)
                                }
                                
                                Slider(value: Binding(
                                    get: { Double(notificationSettings.windSpeedThreshold) },
                                    set: { notificationSettings.windSpeedThreshold = Int($0); saveNotificationSettings() }
                                ), in: 20...80, step: 5)
                                .tint(.cyan)
                                
                                Text("Alert when wind speed exceeds this threshold")
                                    .font(.caption2)
                                    .foregroundColor(theme.textColor.opacity(0.5))
                            }
                            
                            Divider()
                            
                            // Precipitation Probability Threshold  
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("Rain Probability", systemImage: "cloud.drizzle.fill")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(theme.textColor)
                                    Spacer()
                                    Text("\(notificationSettings.precipitationProbabilityThreshold)%")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.teal)
                                }
                                
                                Slider(value: Binding(
                                    get: { Double(notificationSettings.precipitationProbabilityThreshold) },
                                    set: { notificationSettings.precipitationProbabilityThreshold = Int($0); saveNotificationSettings() }
                                ), in: 30...100, step: 10)
                                .tint(.teal)
                                
                                Text("Alert when rain probability exceeds this percentage")
                                    .font(.caption2)
                                    .foregroundColor(theme.textColor.opacity(0.5))
                            }
                            
                            Divider()
                            
                            // Reset Button
                            Button(action: {
                                showResetConfirmation = true
                            }) {
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
                        .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(0.3)))
                    } label: {
                        HStack {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.purple)
                            Text("Advanced Settings")
                                .font(.headline)
                                .foregroundColor(theme.textColor)
                        }
                    }
                    .tint(theme.textColor)
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
        .onChange(of: viewModel.windSpeedUnit) { newUnit in
            guard let oldUnit = previousWindUnit, oldUnit != newUnit else {
                previousWindUnit = newUnit
                return
            }
            
            // Convert wind speed threshold
            let currentThreshold = Double(notificationSettings.windSpeedThreshold)
            let convertedThreshold: Int
            
            if newUnit == .milesPerHour {
                // km/h to mph
                convertedThreshold = Int(round(currentThreshold / 1.609))
            } else {
                // mph to km/h
                convertedThreshold = Int(round(currentThreshold * 1.609))
            }
            
            notificationSettings.windSpeedThreshold = convertedThreshold
            saveNotificationSettings()
            previousWindUnit = newUnit
        }
        .onChange(of: viewModel.temperatureUnit) { newUnit in
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
    
    private func saveNotificationSettings() {
        UserDefaults.standard.notificationSettings = notificationSettings
        NotificationManager.shared.updateSettings(notificationSettings, weather: viewModel.weather, temperatureUnit: viewModel.temperatureUnit)
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
                            .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(0.4)))
                        }
                        
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Open System Settings")
                                .font(.caption)
                                .foregroundColor(theme.textColor.opacity(0.7))
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
                                .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(0.3)))
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
    
    var body: some View {
        ZStack {
            let theme = viewModel.currentTheme(colorScheme: colorScheme)
            AnimatedGradientBackground(colors: [theme.topColor, theme.bottomColor])
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: DesignSystem.spacingXL) {
                    
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
                            .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(0.4)))
                            
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
                                .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(0.4)))
                            }

                            SettingsToggleRow(
                                title: "Icons",
                                icon: "sparkles",
                                color: .yellow,
                                textColor: theme.textColor,
                                isOn: $viewModel.useMinimalistIcons
                            )
                            
                            // App Icons Gallery Navigation
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
                                .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(0.4)))
                            }
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
                                        .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(viewModel.typography == font ? 0.6 : 0.3)))
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
                                    Text("Long-press any widget to enter Edit Mode, then drag to reorder or tap (+) to add new widgets.")
                                        .font(.caption)
                                        .foregroundColor(theme.textColor.opacity(0.6))
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(0.4)))
                        }
                    }
                    
                }
                .padding(DesignSystem.spacingM)
                .frame(width: UIScreen.main.bounds.width)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .navigationTitle("Design Studio")
        .navigationBarTitleDisplayMode(.large)
    }
}



