//
//  ContentView.swift
//  Breezy
//
//  Main weather view
//

import SwiftUI
import Charts
import UniformTypeIdentifiers
import CoreLocation

struct ContentView: View {
    @StateObject private var viewModel = WeatherViewModel()
    @StateObject private var locationHelper = LocationHelper()
    @State private var showingSettings = false
    @State private var showingTimeMachine = false
    @State private var showingLocationPicker = false
    @State private var isButtonBusy = false
    @State private var showingOnboarding = false
    @Environment(\.colorScheme) var colorScheme
    @State private var dashboardWidgets: [DashboardWidget] = DashboardWidget.defaultDashboard
    @State private var gradientColors: [Color] = []
    @State private var isEditMode = false
    @State private var draggingWidget: DashboardWidget?
    @State private var showingWidgetGallery = false
    @State private var configuringWidget: DashboardWidget?


    var body: some View {
        NavigationStack {
            mainContent
                .onAppear {
                    // Check if onboarding should be shown
                    if !UserDefaults.standard.bool(forKey: "Breezy.HasCompletedOnboarding") {
                        showingOnboarding = true
                    } else {
                        viewModel.performStartupIfNeeded(locationHelper: locationHelper)
                    }
                    let theme = viewModel.currentTheme(colorScheme: colorScheme)
                    // Set initial colors without animation
                    gradientColors = [theme.topColor, theme.bottomColor]
                }
                .fullScreenCover(isPresented: $showingOnboarding) {
                    OnboardingView(isPresented: $showingOnboarding, viewModel: viewModel, locationHelper: locationHelper)
                }
                .onChange(of: showingOnboarding) { oldValue, isShowing in
                    if !isShowing && UserDefaults.standard.bool(forKey: "Breezy.HasCompletedOnboarding") {
                        // User just finished onboarding, start the app
                        viewModel.performStartupIfNeeded(locationHelper: locationHelper)
                    }
                }
                .onChange(of: locationHelper.userLocation) { oldValue, newLocation in
                    // Only auto-update if using GPS location
                    let useGPS = UserDefaults.standard.bool(forKey: "Breezy.useGPSLocation")
                    if useGPS, let location = newLocation {
                        Task { await viewModel.fetchWeather(for: location, isManualRefresh: false) }
                    }
                }
                .onChange(of: locationHelper.significantLocationChange) { oldValue, newLocation in
                    // Auto-refresh on significant location changes (only if using GPS)
                    let useGPS = UserDefaults.standard.bool(forKey: "Breezy.useGPSLocation")
                    if useGPS, let location = newLocation {
                        Task { await viewModel.fetchWeather(for: location, isManualRefresh: false) }
                    }
                }
                .onChange(of: viewModel.currentLocation) { oldValue, newLocation in
                    // Auto-refresh when location changes
                    if let location = newLocation, viewModel.weather?.location.city != location.city {
                        Task { await viewModel.fetchWeather(for: location, isManualRefresh: false) }
                    }
                }
                .onAppear {
                    // Start monitoring location changes
                    locationHelper.startMonitoringSignificantLocationChanges()
                    // Load dashboard
                    loadDashboard()
                }
                .onChange(of: viewModel.weather) { oldValue, newValue in
                    let theme = viewModel.currentTheme(colorScheme: colorScheme)
                    withAnimation(.easeInOut(duration: 1.0)) {
                        gradientColors = [theme.topColor, theme.bottomColor]
                    }
                }
                .onChange(of: colorScheme) { oldValue, newValue in
                    // Instant background repaint on theme switch
                    let theme = viewModel.currentTheme(colorScheme: newValue)
                    withAnimation(.easeInOut(duration: 1.0)) {
                        gradientColors = [theme.topColor, theme.bottomColor]
                    }
                }
                // Also listen to explicit theme settings triggers
                .onChange(of: viewModel.themeMode) { _, _ in
                    let theme = viewModel.currentTheme(colorScheme: colorScheme)
                    withAnimation(.easeInOut(duration: 1.0)) {
                        gradientColors = [theme.topColor, theme.bottomColor]
                    }
                }
                .onChange(of: viewModel.selectedPresetThemeName) { _, _ in
                    let theme = viewModel.currentTheme(colorScheme: colorScheme)
                    withAnimation(.easeInOut(duration: 1.0)) {
                        gradientColors = [theme.topColor, theme.bottomColor]
                    }
                }
                .onChange(of: viewModel.customTheme.id) { _, _ in
                    let theme = viewModel.currentTheme(colorScheme: colorScheme)
                    withAnimation(.easeInOut(duration: 1.0)) {
                        gradientColors = [theme.topColor, theme.bottomColor]
                    }
                }
                .onChange(of: viewModel.appearanceMode) { _, _ in
                    let theme = viewModel.currentTheme(colorScheme: colorScheme)
                    withAnimation(.easeInOut(duration: 1.0)) {
                        gradientColors = [theme.topColor, theme.bottomColor]
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        if isEditMode {
                            Button {
                                showingWidgetGallery = true
                            } label: {
                                Image(systemName: "plus")
                                    .fontWeight(.bold)
                                    .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                                    .padding(8)
                                    .background(Circle().fill(.ultraThinMaterial))
                            }
                        } else {
                            Button(action: {
                                showingLocationPicker = true
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "location.fill")
                                        .font(.subheadline)
                                    Text(viewModel.weather?.location.city ?? "Location")
                                        .font(.subheadline.weight(.medium))
                                }
                                .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                            }
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if isEditMode {
                            Button("Done") {
                                withAnimation {
                                    isEditMode = false
                                }
                            }
                            .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                            .fontWeight(.bold)
                        } else {
                            let theme = viewModel.currentTheme(colorScheme: colorScheme)
                            HStack(spacing: 12) {
                                Button {
                                    showingTimeMachine = true
                                } label: {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(theme.textColor)
                                        .frame(width: 36, height: 36)
                                }
                                .accessibilityLabel("Time Machine")
                                
                                Button {
                                    showingSettings = true
                                } label: {
                                    Image(systemName: "gearshape.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(theme.textColor)
                                        .frame(width: 36, height: 36)
                                }
                                .accessibilityLabel("Settings")
                            }
                        }
                    }
                }
                // Listen for dashboard changes
                .onReceive(NotificationCenter.default.publisher(for: WeatherSection.sectionOrderChanged)) { _ in
                    loadDashboard()
                }
                .onReceive(NotificationCenter.default.publisher(for: .cloudDataReconciled)) { _ in
                    loadDashboard()
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView(viewModel: viewModel)
                }
                .sheet(isPresented: $showingTimeMachine) {
                    TimeMachineView(viewModel: viewModel)
                }
                .sheet(isPresented: $showingWidgetGallery) {
                    WidgetGalleryView(viewModel: viewModel, onAdd: { widgetType in
                        withAnimation {
                            let newWidget = DashboardWidget(
                                id: UUID(),
                                type: widgetType,
                                visibleMetrics: widgetType == .deepDetails ? Array(WeatherMetric.allCases.shuffled().prefix(3)) : nil
                            )
                            dashboardWidgets.append(newWidget)
                            saveDashboard()
                            showingWidgetGallery = false
                        }
                    })
                }
                .sheet(item: $configuringWidget) { widget in
                    WidgetConfigView(widget: widget, viewModel: viewModel, onSave: { updatedWidget in
                        if let index = dashboardWidgets.firstIndex(where: { $0.id == updatedWidget.id }) {
                            dashboardWidgets[index] = updatedWidget
                            saveDashboard()
                        }
                    })
                }
                .sheet(isPresented: $showingLocationPicker) {
                    LocationPickerView(viewModel: viewModel, locationHelper: locationHelper, isButtonBusy: $isButtonBusy)
                }
                .toolbarColorScheme(viewModel.currentTheme(colorScheme: colorScheme).isDark ? .dark : .light, for: .navigationBar)
        }
    }
    
    private var mainContent: some View {
        ZStack {
            let theme = viewModel.currentTheme(colorScheme: colorScheme)
            
            // Soft pastel gradient background
            PastelGradientBackground(
                colors: gradientColors.isEmpty ? [theme.topColor, theme.bottomColor] : gradientColors
            )
            
            // Floating ambient particles
            FloatingParticles()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: DesignSystem.spacingXL) {
                    Spacer()
                        .frame(height: DesignSystem.spacingS)

                    if let locErr = locationHelper.locationError {
                        EmptyStateView(state: .error(locErr)) {
                            showingLocationPicker = true
                        }
                        .padding(.top, 40)
                    }

                    if let weather = viewModel.weather {
                        // Main weather display
                        NewWeatherHeaderView(weather: weather, viewModel: viewModel)
                        
                        // Render widgets in user-defined order
                        ForEach(dashboardWidgets) { widget in
                            EditableSectionContainer(
                                sectionId: widget.id,
                                isEditMode: isEditMode,
                                onRemove: {
                                    withAnimation {
                                        dashboardWidgets.removeAll { $0.id == widget.id }
                                        saveDashboard()
                                    }
                                },
                                onConfigure: widget.type == .deepDetails ? {
                                    configuringWidget = widget
                                } : nil,
                                content: {
                                    renderWidget(widget, weather: weather)
                                }
                            )
                            .contentShape(Rectangle()) // Ensure entire area is valid for drag
                            .onDrag {
                                self.draggingWidget = widget
                                return NSItemProvider(object: widget.id.uuidString as NSString)
                            } preview: {
                                renderWidget(widget, weather: weather)
                                    .frame(width: 300) // Fixed width for preview to avoid layout glitches
                                    .contentShape(Rectangle())
                            }
                            .onDrop(of: [.text], delegate: WidgetDropDelegate(item: widget, list: $dashboardWidgets, draggingItem: $draggingWidget, onSave: saveDashboard))
                        }
                        
                    } else if viewModel.isLoading {
                        WeatherLoadingSkeleton()
                    } else if let error = viewModel.error {
                        EmptyStateView(state: .error(error)) {
                            Task {
                                if let loc = viewModel.currentLocation {
                                    await viewModel.fetchWeather(for: loc, isManualRefresh: true)
                                }
                            }
                        }
                        .padding(.top, 40)
                    } else {
                        EmptyStateView(state: .noLocation) {
                             showingLocationPicker = true
                        }
                        .padding(.top, 40)
                    }
                    
                    Spacer()
                        .frame(height: DesignSystem.spacingXL)
                }
            }
            .refreshable {
                HapticsManager.shared.impact(style: .medium)
                if viewModel.shouldFollowGPS {
                    // Re-acquire GPS location on pull-to-refresh
                    if let location = try? await locationHelper.requestLocationAndGetData() {
                        await viewModel.fetchWeather(for: location, isManualRefresh: true)
                    }
                } else if let location = viewModel.currentLocation {
                    await viewModel.fetchWeather(for: location, isManualRefresh: true)
                }
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 1.5, maximumDistance: 50)
                .onEnded { _ in
                    if !isEditMode {
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        withAnimation(.spring()) {
                            isEditMode = true
                        }
                    }
                }
        )
    }
    
    // MARK: - Dashboard Rendering Functions
    
    private func loadDashboard() {
        // Try loading modern DashboardWidgets
        if let data = CloudStorage.shared.data(forKey: "Breezy.DashboardWidgets") {
            if let decoded = try? JSONDecoder().decode([DashboardWidget].self, from: data) {
                // Filter out any widgets that might have invalid types if decoding succeeded but enum changed
                dashboardWidgets = decoded
                return
            }
        }
        
        // Try migrating legacy WeatherSection
        if let data = UserDefaults.standard.data(forKey: "Breezy.SectionOrder") {
            if let decoded = try? JSONDecoder().decode([WeatherSection].self, from: data) {
                // Migration from WeatherSection to DashboardWidget
                dashboardWidgets = decoded.compactMap { section in
                    switch section {
                    case .hourlyForecast: return DashboardWidget(id: UUID(), type: .hourlyForecast)
                    case .dailyForecast: return DashboardWidget(id: UUID(), type: .dailyForecast)
                    case .metricsPills: return DashboardWidget(id: UUID(), type: .deepDetails, visibleMetrics: Array(viewModel.visibleMetrics))
                    case .sunMoon: return nil
                    }
                }
                saveDashboard()
                UserDefaults.standard.removeObject(forKey: "Breezy.SectionOrder") // Clean up
                return
            }
        }
        
        // Fallback to defaults
        print("Using default dashboard config")
        dashboardWidgets = DashboardWidget.defaultDashboard
    }
    
    private func saveDashboard() {
        if let encoded = try? JSONEncoder().encode(dashboardWidgets) {
            CloudStorage.shared.set(encoded, forKey: "Breezy.DashboardWidgets")
            // Removed redundant notification post to prevent reload loops
        }
    }
    
    @ViewBuilder
    private func renderWidget(_ widget: DashboardWidget, weather: WeatherInfo) -> some View {
        switch widget.type {
        case .hourlyForecast:
            NewHourlyCardView(
                hourlyData: weather.hourlyForecast,
                allHourlyData: weather.allHourlyData,
                viewModel: viewModel
            )
            .padding(.horizontal, DesignSystem.spacingM)
            
        case .dailyForecast:
            NewDailyForecastView(forecast: weather.dailyForecast, viewModel: viewModel)
                .padding(.horizontal, DesignSystem.spacingM)
            
        case .deepDetails:
            if let metrics = weather.metrics {
                let metricsToUse = widget.visibleMetrics ?? Array(viewModel.visibleMetrics)
                MetricsPillsView(metrics: metrics, weather: weather, viewModel: viewModel, customMetrics: metricsToUse)
                    .padding(.horizontal, DesignSystem.spacingM)
            }
            
        case .rainSummary:
            RainSummaryWidget(weather: weather, viewModel: viewModel)
                .padding(.horizontal, DesignSystem.spacingM)
                
        case .windSummary:
            if widget.config?["style"] == "rose", let metrics = weather.metrics {
               // Extract speed (remove " km/h" etc)
                let speedString = metrics.windSpeed?.components(separatedBy: CharacterSet.decimalDigits.inverted).joined() ?? "0"
                let speed = Double(speedString) ?? 0
                
                VStack(alignment: .leading, spacing: 12) {
                    Label("Wind Rose", systemImage: "wind")
                        .font(.caption.weight(.bold))
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.6))
                        .padding(.horizontal)
                        .padding(.top, 16)
                    
                    WindRoseView(
                        speed: speed,
                        direction: metrics.windDirectionCardinal ?? "N",
                        degree: metrics.windDirection ?? 0,
                        color: viewModel.currentTheme(colorScheme: colorScheme).textColor
                    )
                    .padding(.bottom, 16)
                    .padding(.horizontal)
                }
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                        .fill(.ultraThinMaterial.opacity(0.35))
                        .overlay(RoundedRectangle(cornerRadius: DesignSystem.radiusL).stroke(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.18), lineWidth: 0.5))
                )
                .shadow(color: Color.black.opacity(0.15), radius: 18, x: 0, y: 10)
                .padding(.horizontal, DesignSystem.spacingM)
            } else {
                WindSummaryWidget(weather: weather, viewModel: viewModel)
                    .padding(.horizontal, DesignSystem.spacingM)
            }
                
        case .radar:
            RadarCardView(viewModel: viewModel)
                .padding(.horizontal, DesignSystem.spacingM)
                
        case .uvIndex:
            UVIndexWidget(weather: weather, viewModel: viewModel)
                .padding(.horizontal, DesignSystem.spacingM)
                
        case .feelsLike:
            FeelsLikeWidget(weather: weather, viewModel: viewModel)
                .padding(.horizontal, DesignSystem.spacingM)
                
        case .sunPath:
            if let sunrise = weather.metrics?.sunrise, let sunset = weather.metrics?.sunset, 
               let sunriseDate = DateFormatterHelper.parseTime(sunrise, timeZone: TimeZone(identifier: weather.timezone) ?? .current),
               let sunsetDate = DateFormatterHelper.parseTime(sunset, timeZone: TimeZone(identifier: weather.timezone) ?? .current) {
                
                VStack(alignment: .leading, spacing: 0) {
                    Label("Sun Path", systemImage: "sun.max.fill")
                        .font(.caption.weight(.bold))
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.6))
                        .padding(.horizontal)
                        .padding(.top, 16)
                    
                    SunPathView(
                        sunrise: sunriseDate,
                        sunset: sunsetDate,
                        currentTime: Date(),
                        textColor: viewModel.currentTheme(colorScheme: colorScheme).textColor
                    )
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                    .padding(.horizontal)
                }
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                        .fill(.ultraThinMaterial.opacity(0.35))
                        .overlay(RoundedRectangle(cornerRadius: DesignSystem.radiusL).stroke(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.18), lineWidth: 0.5))
                )
                .shadow(color: Color.black.opacity(0.15), radius: 18, x: 0, y: 10)
                .padding(.horizontal, DesignSystem.spacingM)
            }
            
        case .moonPhase:
            if let today = weather.dailyForecast.first, let phase = today.moonPhase {
                VStack(alignment: .leading, spacing: 0) {
                    Label("Moon Phase", systemImage: "moon.stars.fill")
                        .font(.caption.weight(.bold))
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.6))
                        .padding(.horizontal)
                        .padding(.top, 16)
                        
                    HStack(spacing: 24) {
                        MoonPhaseView2(
                            phase: phase,
                            size: 70,
                            color: viewModel.currentTheme(colorScheme: colorScheme).textColor
                        )
                        
                        Divider()
                            .frame(height: 60)
                            .background(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.2))
                        
                        VStack(alignment: .leading, spacing: 14) {
                            if let rise = today.moonrise {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.6))
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text("Moonrise").font(.caption2).opacity(0.7)
                                        Text(rise).font(.subheadline.bold())
                                    }
                                }
                            }
                            if let set = today.moonset {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.6))
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text("Moonset").font(.caption2).opacity(0.7)
                                        Text(set).font(.subheadline.bold())
                                    }
                                }
                            }
                        }
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                        
                        Spacer()
                    }
                    .padding(20)
                }
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                        .fill(.ultraThinMaterial.opacity(0.35))
                        .overlay(RoundedRectangle(cornerRadius: DesignSystem.radiusL).stroke(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.18), lineWidth: 0.5))
                )
                .shadow(color: Color.black.opacity(0.15), radius: 18, x: 0, y: 10)
                .padding(.horizontal, DesignSystem.spacingM)
            }

            
        case .uvIndexCurve:
            if let hourly = weather.allHourlyData {
                VStack(alignment: .leading, spacing: 0) {
                    Label("UV Index", systemImage: "aqi.medium")
                        .font(.caption.weight(.bold))
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.6))
                        .padding(.horizontal)
                        .padding(.top, 16)

                    UVIndexCurveView(
                        hourlyForecast: hourly,
                        currentUV: weather.metrics?.uvIndex ?? 0,
                        colorScheme: colorScheme
                    )
                    .padding(.bottom, 16)
                }
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                        .fill(.ultraThinMaterial.opacity(0.35))
                        .overlay(RoundedRectangle(cornerRadius: DesignSystem.radiusL).stroke(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.18), lineWidth: 0.5))
                )
                .shadow(color: Color.black.opacity(0.15), radius: 18, x: 0, y: 10)
                .padding(.horizontal, DesignSystem.spacingM)
            }
        }
    }
}

// MARK: - Supporting Views

struct WeatherHeaderView: View {
    let weather: WeatherInfo
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    
    
    
    var body: some View {
        ZStack {
            Circle()
                .fill(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.15))
                .frame(width: 220, height: 220)
                .blur(radius: 80)
                .offset(x: -50, y: -30)
            
            Circle()
                .fill(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.12))
                .frame(width: 160, height: 160)
                .blur(radius: 70)
                .offset(x: 60, y: 25)
            
            VStack(spacing: 10) {
                if viewModel.useMinimalistIcons {
                    Image(systemName: viewModel.weatherIcon(for: weather.condition))
                        .font(.system(size: 54, weight: .light)) // Smaller icon
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                        .symbolRenderingMode(.hierarchical)
                        .padding(.bottom, 4)
                } else {
                    Text(weather.emoji)
                        .font(.system(size: 48)) // Smaller emoji
                        .padding(.bottom, 4)
                }
                
                Text(weather.temperature)
                    .font(.system(size: 56, weight: .bold, design: viewModel.typography.design))
                    .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                    .accessibilityLabel("Temperature: \(weather.temperature)")
                
                if let feelsLike = weather.feelsLike {
                    Text("Feels like \(feelsLike)")
                        .font(.title3)
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.8))
                        .accessibilityLabel("Feels like \(feelsLike)")
                }
                
                if let high = weather.highTemp, let low = weather.lowTemp {
                    HStack(spacing: 6) {
                        Text("H: \(high)")
                            .font(.body)
                            .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.75))
                        Text("•")
                            .font(.body)
                            .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.5))
                        Text("L: \(low)")
                            .font(.body)
                            .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.75))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("High: \(high), Low: \(low)")
                }
                
                Text(weather.condition)
                    .font(.title3)
                    .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.85))
                    .accessibilityLabel("Condition: \(weather.condition)")
            }
        }
    }
}

struct HourlyForecastChartView: View {
    let hourlyData: [HourlyForecast] // Every 3 hours for display
    let allHourlyData: [HourlyForecast]? // Not used anymore, kept for compatibility
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    // Interactive scrubbing state for main view
    @State private var selectedHourValue: Int? = nil
    @State private var dragX: CGFloat? = nil
    @State private var isDragging: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.title3.weight(.semibold))
                .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                .padding(.horizontal)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("Today's hourly forecast")
            
            ZStack {
                RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                    .fill(.ultraThinMaterial.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                            .stroke(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.18), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.15), radius: 18, x: 0, y: 10)
                    .frame(height: 200)
                    .padding(.horizontal, 12)

                // Prefer per-hour data when available for a smoother chart; fallback to 3-hour data
                let dataSource = (allHourlyData?.isEmpty == false) ? (allHourlyData!) : hourlyData
                // Precompute min/max hours so we can avoid rendering labels that would overflow the rounded card edges
                let minHour = dataSource.map { $0.hourValue }.min() ?? 0
                let maxHour = dataSource.map { $0.hourValue }.max() ?? 23
                let nowHour = Calendar.current.component(.hour, from: Date())

                Chart(dataSource) { hour in
                    // Subtle area fill
                    AreaMark(
                        x: .value("Hour", hour.hourValue),
                        y: .value("Temperature", hour.temperatureRaw)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.white.opacity(0.15), Color.clear]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // Main temperature line
                    LineMark(
                        x: .value("Hour", hour.hourValue),
                        y: .value("Temperature", hour.temperatureRaw)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))

                    // Only show labels for major ticks; do not render point markers for every hour
                    let chartAxisStride = 3
                    // Avoid rendering labels that would stick outside the rounded card at the very edges
                    if hour.hourValue % chartAxisStride == 0 && hour.hourValue != minHour && hour.hourValue != maxHour {
                        PointMark(
                            x: .value("Hour", hour.hourValue),
                            y: .value("Temperature", hour.temperatureRaw)
                        )
                        .symbolSize(0.1)
                        .foregroundStyle(Color.clear)
                        .annotation(position: .top, alignment: .center, spacing: 4) {
                            Text(viewModel.formattedTemperature(hour.temperatureRaw))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                        }
                    }

                    // Show a visible dot for selected hour or 'Now' hour
                    if hour.hourValue == selectedHourValue || hour.hourValue == nowHour {
                        PointMark(
                            x: .value("Hour", hour.hourValue),
                            y: .value("Temperature", hour.temperatureRaw)
                        )
                        .symbolSize(hour.hourValue == selectedHourValue ? 100 : 60)
                        .foregroundStyle(hour.hourValue == selectedHourValue ? Color.yellow : viewModel.currentTheme(colorScheme: colorScheme).textColor)
                    }

                    // Highlight the current hour with a subtle vertical rule and 'Now' label inside the Chart
                    RuleMark(x: .value("Now", nowHour))
                        .foregroundStyle(Color.yellow.opacity(0.9))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4,6]))
                        .annotation(position: .top, alignment: .center) {
                            if let currentTemp = viewModel.weather?.hourlyForecast.first(where: { $0.hourValue == nowHour })?.temperatureRaw {
                                VStack(spacing: 2) {
                                    Text("Now")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(.yellow)
                                    Text(viewModel.formattedTemperature(currentTemp))
                                        .font(.caption2)
                                        .foregroundColor(.yellow)
                                }
                            } else if let currentTempStr = viewModel.weather?.temperature {
                                // Fallback to current temperature string
                                Text("Now: \(currentTempStr)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(.yellow)
                            }
                        }
                }

                // Expand x-axis domain slightly so the curve visually reaches the card edges
                .chartXScale(domain: {
                    let hours = dataSource.map { $0.hourValue }
                    let minH = hours.min() ?? 0
                    let maxH = hours.max() ?? 23
                    return Double(minH) - 0.5...Double(maxH) + 0.5
                }())

                .chartXAxis {
                    AxisMarks(values: .stride(by: 3)) { value in
                        AxisValueLabel {
                            if let hourInt = value.as(Int.self), hourInt >= 0 && hourInt < 24 {
                                Text(hourInt == 0 ? "12 AM" : hourInt < 12 ? "\(hourInt) AM" : hourInt == 12 ? "12 PM" : "\(hourInt - 12) PM")
                                    .font(.system(size: 11))
                                    .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.7))
                            }
                        }
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 180)
                .padding(.vertical, 20)
                .padding(.horizontal, 12)

                // Overlay for handling drag gestures and displaying tooltip (interactive scrubbing)
                .overlay {
                    GeometryReader { g in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        isDragging = true
                                        let localX = value.location.x - 12 // account for chart horizontal padding
                                        let width = max(1, g.size.width - 24)
                                        let ratio = min(max(localX / width, 0), 1)
                                        let idx = Int(round(ratio * CGFloat(max(dataSource.count - 1, 0))))
                                        if dataSource.indices.contains(idx) {
                                            selectedHourValue = dataSource[idx].hourValue
                                            dragX = value.location.x
                                        }
                                    }
                                    .onEnded { _ in
                                        isDragging = false
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            selectedHourValue = nil
                                            dragX = nil
                                        }
                                    }
                            )
                            .overlay(alignment: .topLeading) {
                                    if let x = dragX, let selVal = selectedHourValue, let selected = dataSource.first(where: { $0.hourValue == selVal }) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(selected.time)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                                        Text(viewModel.formattedTemperature(selected.temperatureRaw, decimals: 1))
                                            .font(.headline)
                                            .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                                        HStack(spacing: 8) {
                                            Text(selected.emoji)
                                            if let precip = selected.precipitationChance {
                                                Text("\(Int(precip * 100))%")
                                            }
                                            if let wind = selected.windSpeed {
                                                Text(wind)
                                            }
                                        }
                                        .font(.caption2)
                                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.85))
                                    }
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.6)))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                                    .frame(maxWidth: 180)
                                    .position(x: min(max(x, 60), g.size.width - 60), y: 24)
                                    .transition(.opacity)
                                }
                            }
                    }
                }
            }
        }
        .padding(.top, 8)
    }
}

struct HourDetailSheet: View {
    let hour: HourlyForecast
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.8)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Text(hour.emoji)
                        .font(.system(size: 80))
                    
                    Text(hour.time)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                    
                    Text(viewModel.formattedTemperature(hour.temperatureRaw))
                        .font(.system(size: 64, weight: .light))
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                    
                    Text(hour.condition)
                        .font(.title2)
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.9))
                }
            }
            .navigationTitle("Hour Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                }
            }
        }
    }
}

struct DailyForecastListView: View {
    let forecast: [DailyForecast]
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("10-Day Forecast")
                .font(.title3.weight(.semibold))
                .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                .padding(.horizontal)
            
            VStack(spacing: 8) {
                ForEach(forecast) { day in
                    NavigationLink(destination: DailyForecastDetailView(day: day, viewModel: viewModel)) {
                        DailyForecastRowView(day: day, viewModel: viewModel)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .modernCard(padding: 0, cornerRadius: DesignSystem.radiusL)
                }
            }
            .padding(.horizontal)
        }
        .padding(.top, 8)
    }
}

struct DailyForecastRowView: View {
    let day: DailyForecast
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            Text(day.dayName)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                .frame(width: 60, alignment: .leading)
            
            if viewModel.useMinimalistIcons {
                Image(systemName: viewModel.weatherIcon(for: day.condition))
                    .font(.title3)
                    .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 30)
            } else {
                Text(day.emoji)
                    .font(.title3)
                    .frame(width: 30)
            }
            
            Text(day.condition)
                .font(.caption)
                .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.8))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 8) {
                Text(day.lowTemp)
                    .font(.body)
                    .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.6))
                Text(day.highTemp)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.6))
        }
        .padding()
        .background(Color.white.opacity(0.001)) // improve tap target without changing look
    }
}

// MARK: - Today Highlights

struct TodayHighlightsView: View {
    let weather: WeatherInfo
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    
    private var today: DailyForecast? {
        weather.dailyForecast.first
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
                // Show a compact contextual pill (e.g., "Rain within ~1 hour") when appropriate
                if let rainLabel = viewModel.rainSoonLabel {
                    HStack {
                        Text(rainLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.12))
                            )
                    }
                    .padding(.horizontal, 6)
                }

            GeometryReader { geo in
                let items: [(icon: String, title: String, value: String)] = {
                    var arr: [(String, String, String)] = []
                    if let chance = today?.chanceOfRain {
                        arr.append(("cloud.rain.fill", "Rain chance", chance))
                    }
                    if let metrics = weather.metrics, let humidity = metrics.humidity {
                        arr.append(("humidity.fill", "Humidity", "\(humidity)%"))
                    }
                    if let metrics = weather.metrics, let uv = metrics.uvIndex, metrics.uvIndexCategory != nil {
                        arr.append(("sun.max.fill", "UV Index", "\(uv)"))
                    }
                    if let metrics = weather.metrics, let windSpeed = metrics.windSpeed, metrics.windDirectionCardinal != nil {
                        arr.append(("wind", "Wind", windSpeed))
                    }
                    return arr
                }()

                let count = max(1, items.count)
                let columns = min(count, 3)
                let spacing: CGFloat = 4
                let totalSpacing = CGFloat(columns - 1) * spacing
                let cardWidth = floor((geo.size.width - totalSpacing) / CGFloat(columns))

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: spacing) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HighlightCard(
                                icon: item.icon,
                                title: item.title,
                                value: item.value,
                                subtitle: nil,
                                textColor: viewModel.currentTheme(colorScheme: colorScheme).textColor
                            )
                            .frame(width: max(100, cardWidth), height: 86)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 14)
                }
            }
            .frame(height: 110)
        }
    }
}

struct HighlightCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String?
    let textColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(textColor)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundColor(textColor.opacity(0.8))
            }
            
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundColor(textColor)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(textColor.opacity(0.7))
            }
        }
        .padding(8)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                    .fill(.ultraThinMaterial.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                            .stroke(textColor.opacity(0.2), lineWidth: 0.5)
                    )
            )
                .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 6)
            .frame(height: 86, alignment: .leading)
    }
}

// MARK: - Sun & Moon Summary

// MARK: - New Weather Mini Style Components

// MARK: - New Weather Mini Style Components

struct NewWeatherHeaderView: View {
    let weather: WeatherInfo
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: DesignSystem.spacingM) {
            // Giant animated weather icon
            if viewModel.useMinimalistIcons {
                AnimatedWeatherIcon(
                    systemName: viewModel.weatherIcon(for: weather.condition),
                    size: 140,
                    condition: weather.condition,
                    colorScheme: colorScheme
                )
                .padding(.top, DesignSystem.spacingL)
            } else {
                EmojiAnimatedIcon(emoji: weather.emoji, size: 140, condition: weather.condition)
                    .padding(.top, DesignSystem.spacingL)
            }
            
            // Huge temperature
            Text(weather.temperature)
                .font(.system(size: 72, weight: .thin))
                .fontDesign(viewModel.typography.design)
                .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                .accessibilityLabel("Temperature: \(weather.temperature)")
            
            // Feels Like - Prominent display
            if let feelsLike = weather.feelsLike {
                HStack(spacing: 6) {
                    if viewModel.useMinimalistIcons {
                        Image(systemName: "thermometer.medium")
                            .font(.caption)
                    } else {
                        Text("🌡")
                            .font(.caption)
                    }
                    Text("Feels like \(feelsLike)")
                        .font(.title3.weight(.medium))
                }
                .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.85))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial.opacity(0.3))
                        .overlay(
                            Capsule()
                                .stroke(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.2), lineWidth: 1)
                        )
                )
                .accessibilityLabel("Feels like \(feelsLike)")
            }
            
            // Condition
            Text(weather.condition)
                .font(.title2.weight(.medium))
                .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.9))
                .accessibilityLabel("Condition: \(weather.condition)")
            
            // High/Low
            if let high = weather.highTemp, let low = weather.lowTemp {
                HStack(spacing: 8) {
                    Text("H: \(high)")
                        .font(.body)
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.8))
                    Text("•")
                        .font(.body)
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.5))
                    Text("L: \(low)")
                        .font(.body)
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.8))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("High: \(high), Low: \(low)")
            }
        }
        .padding(.vertical, DesignSystem.spacingL)
    }
}

struct NewHourlyCardView: View {
    let hourlyData: [HourlyForecast]
    let allHourlyData: [HourlyForecast]?
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var scrollViewId = UUID()
    
    // Find the index of the current hour (or closest hour)
    private var currentHourIndex: Int {
        let currentHour = Calendar.current.component(.hour, from: Date())
        
        // Use allHourlyData if available, otherwise fall back to hourlyData
        let dataToUse = allHourlyData ?? hourlyData
        
        // Find the first hour that matches or is after the current hour
        if let index = dataToUse.firstIndex(where: { hour in
            // Try to extract hour from time string (e.g., "Now", "2 PM", "14:00")
            if hour.time.lowercased() == "now" {
                return true
            }
            
            // Parse hour from time string
            if let hourValue = extractHour(from: hour.time) {
                return hourValue >= currentHour
            }
            return false
        }) {
            return index
        }
        
        return 0
    }
    
    private func extractHour(from timeString: String) -> Int? {
        // Handle formats like "2 PM", "14:00", "2pm"
        let cleaned = timeString.replacingOccurrences(of: " ", with: "").lowercased()
        
        if cleaned.contains("pm") {
            let hourStr = cleaned.replacingOccurrences(of: "pm", with: "")
            if let hour = Int(hourStr) {
                return hour == 12 ? 12 : hour + 12
            }
        } else if cleaned.contains("am") {
            let hourStr = cleaned.replacingOccurrences(of: "am", with: "")
            if let hour = Int(hourStr) {
                return hour == 12 ? 0 : hour
            }
        } else if let hour = Int(cleaned.prefix(2)) {
            return hour
        }
        
        return nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("24-Hour Forecast", systemImage: "chart.xyaxis.line")
                .font(.caption.weight(.bold))
                .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.6))
            
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DesignSystem.spacingS) {
                        // Show all available hourly data (up to 24 hours)
                        let hoursToShow = allHourlyData ?? hourlyData
                        let theme = viewModel.currentTheme(colorScheme: colorScheme)
                        
                        ForEach(0..<min(24, hoursToShow.count), id: \.self) { index in
                            let hour = hoursToShow[index]
                            VStack(spacing: 8) {
                                Text(hour.time)
                                    .font(.caption.weight(index == currentHourIndex ? .bold : .medium))
                                    .foregroundColor(theme.textColor.opacity(index == currentHourIndex ? 1.0 : 0.75))
                                
                                if viewModel.useMinimalistIcons {
                                    Image(systemName: viewModel.weatherIcon(for: hour.condition))
                                        .font(.title3)
                                        .foregroundColor(theme.textColor)
                                        .symbolRenderingMode(.hierarchical)
                                        .frame(height: 28)
                                } else {
                                    Text(hour.emoji)
                                        .font(.title3)
                                        .frame(height: 28)
                                }
                                
                                Text(viewModel.formattedTemperature(hour.temperatureRaw))
                                    .font(.body.weight(index == currentHourIndex ? .bold : .semibold))
                                    .foregroundColor(theme.textColor)
                            }
                            .frame(width: 60)
                            .id(index) // Ensure ID matches the index
                            .padding(.vertical, DesignSystem.spacingS)
                            .background(
                                RoundedRectangle(cornerRadius: DesignSystem.radiusS)
                                    .fill(index == currentHourIndex ? Color.white.opacity(0.25) : Color.clear)
                            )
                        }
                    }
                    .padding(.horizontal, DesignSystem.spacingM)
                }
                .onAppear {
                    scrollToCurrentHour(proxy: proxy)
                }
                .onChange(of: hourlyData.count) { _, _ in
                    scrollToCurrentHour(proxy: proxy)
                }
            }
        }
        .softGlassCard(padding: DesignSystem.spacingM, cornerRadius: DesignSystem.radiusM)
    }
    
    private func scrollToCurrentHour(proxy: ScrollViewProxy) {
        // Auto-scroll to current hour with animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.8)) {
                proxy.scrollTo(currentHourIndex, anchor: .center)
            }
        }
    }
}

struct NewDailyForecastView: View {
    let forecast: [DailyForecast]
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("10-Day Forecast", systemImage: "calendar")
                .font(.caption.weight(.bold))
                .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.6))
            
            VStack(spacing: DesignSystem.spacingXS) {
                ForEach(forecast.prefix(10)) { day in
                    NavigationLink(destination: DailyForecastDetailView(day: day, viewModel: viewModel)) {
                        SimpleDailyRow(day: day, viewModel: viewModel)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, DesignSystem.spacingM)
        }
        .softGlassCard(padding: DesignSystem.spacingM, cornerRadius: DesignSystem.radiusM)
    }
}

struct SimpleDailyRow: View {
    let day: DailyForecast
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            // Day name
            Text(day.dayName)
                .font(.body.weight(.medium))
                .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 90, alignment: .leading)
            
            // Icon
            if viewModel.useMinimalistIcons {
                Image(systemName: viewModel.weatherIcon(for: day.condition))
                    .font(.title3)
                    .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 30)
            } else {
                Text(day.emoji)
                    .font(.title3)
                    .frame(width: 30)
            }
            
            Spacer()
            
            // Temps
            HStack(spacing: 10) {
                Text(day.lowTemp)
                    .font(.body)
                    .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.6))
                Text(day.highTemp)
                    .font(.body.weight(.semibold))
                    .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
            }
        }
        .padding(.vertical, DesignSystem.spacingXS)
    }
}

struct MetricsPillsView: View {
    let metrics: WeatherMetrics
    let weather: WeatherInfo
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    var customMetrics: [WeatherMetric]? = nil
    
    var body: some View {
        let pills = buildPills()
        
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: DesignSystem.spacingS) {
            ForEach(pills, id: \.title) { pill in
                VStack(spacing: 6) {
                    // Show emoji or SF Symbol based on setting
                    if viewModel.useMinimalistIcons {
                        Image(systemName: pill.icon)
                            .font(.title3)
                            .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.9))
                    } else {
                        Text(pill.emoji)
                            .font(.title3)
                    }
                    
                    Text(pill.title)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.7))
                    
                    Text(pill.value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.spacingM)
                .softGlassCard(padding: DesignSystem.spacingS, cornerRadius: DesignSystem.radiusS)
            }
        }
    }
    
    private func buildPills() -> [(icon: String, emoji: String, title: String, value: String)] {
        var pills: [(String, String, String, String)] = []
        let visibleList = customMetrics ?? Array(viewModel.visibleMetrics)
        
        // Iterate through all metrics, but only add if they are visible AND have data
        for metric in WeatherMetric.allCases {
            guard visibleList.contains(metric) else { continue }
            
            switch metric {
            case .wind:
                if let wind = metrics.windSpeed {
                    pills.append((metric.icon, metric.emoji, metric.rawValue, wind))
                }
            case .humidity:
                if let humidity = metrics.humidity {
                    pills.append((metric.icon, metric.emoji, metric.rawValue, "\(humidity)%"))
                }
            case .uvIndex:
                if let uv = metrics.uvIndex {
                    pills.append((metric.icon, metric.emoji, metric.rawValue, "\(uv)"))
                }
            case .visibility:
                if let vis = metrics.visibility {
                    pills.append((metric.icon, metric.emoji, metric.rawValue, vis))
                }
            case .pressure:
                if let press = metrics.pressure {
                    pills.append((metric.icon, metric.emoji, metric.rawValue, press))
                }
            case .dewPoint:
                if let dew = metrics.dewPoint {
                    pills.append((metric.icon, metric.emoji, metric.rawValue, dew))
                }
            case .rain:
                if let rain = metrics.rainChance {
                    pills.append((metric.icon, metric.emoji, metric.rawValue, rain))
                } else if let rain = weather.dailyForecast.first?.chanceOfRain {
                     // Fallback to today's chance
                    pills.append((metric.icon, metric.emoji, metric.rawValue, rain))
                }
            case .cloudCover:
                if let cloud = metrics.cloudCover {
                    pills.append((metric.icon, metric.emoji, metric.rawValue, cloud))
                }
            case .feelsLike:
                if let feels = weather.feelsLike {
                    pills.append((metric.icon, metric.emoji, metric.rawValue, feels))
                }
            case .sunset:
                if let sunset = metrics.sunset {
                    pills.append((metric.icon, metric.emoji, metric.rawValue, sunset))
                }
            case .sunrise:
                if let sunrise = weather.dailyForecast.first?.sunrise {
                    pills.append((metric.icon, metric.emoji, metric.rawValue, sunrise))
                }
            }
        }
        
        return pills
    }
}

// MARK: - New Widgets

struct RainSummaryWidget: View {
    let weather: WeatherInfo
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Precipitation", systemImage: "cloud.rain.fill")
                .font(.caption.weight(.bold))
                .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.6))
            
            VStack(alignment: .leading, spacing: 12) {
                if let soon = viewModel.rainSoonLabel {
                    Text(soon)
                        .font(.headline)
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                } else {
                    Text("No rain expected soon")
                        .font(.subheadline)
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.7))
                }
                
                if let today = weather.dailyForecast.first {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading) {
                            Text(today.chanceOfRain ?? "0%")
                                .font(.title3.weight(.bold))
                            Text("Chance")
                                .font(.caption2)
                                .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.6))
                        }
                        
                        if let accumulated = weather.metrics?.rainChance {
                            VStack(alignment: .leading) {
                                Text(accumulated)
                                    .font(.title3.weight(.bold))
                                Text("Accumulation")
                                    .font(.caption2)
                                    .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.6))
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softGlassCard()
    }
}

struct WindSummaryWidget: View {
    let weather: WeatherInfo
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Wind Conditions", systemImage: "wind")
                .font(.caption.weight(.bold))
                .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.6))
            
            if let metrics = weather.metrics {
                let speedString = metrics.windSpeed?.components(separatedBy: CharacterSet.decimalDigits.inverted).joined() ?? "0"
                let speed = Double(speedString) ?? 0
                
                WindRoseView(
                    speed: speed,
                    direction: metrics.windDirectionCardinal ?? "N",
                    degree: metrics.windDirection ?? 0,
                    color: viewModel.currentTheme(colorScheme: colorScheme).textColor
                )
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softGlassCard()
    }
}

// MARK: - Edit Mode Components

struct EditableSectionContainer<Content: View>: View {
    let sectionId: UUID
    let isEditMode: Bool
    let onRemove: () -> Void
    var onConfigure: (() -> Void)? = nil
    let content: () -> Content
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            content()
                .allowsHitTesting(!isEditMode)
                .jiggle(enabled: isEditMode)
                .scaleEffect(isEditMode ? 0.98 : 1.0)
            
            if isEditMode {
                HStack(spacing: 8) {
                    if let onConfigure = onConfigure {
                        Button(action: onConfigure) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.body)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Circle().fill(.blue))
                        }
                    }
                    
                    Button(action: onRemove) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                            .background(Circle().fill(.white).padding(2))
                    }
                }
                .padding(8)
                .transition(.scale.combined(with: .opacity))
                .zIndex(2)
            }
        }
    }
}

struct WidgetDropDelegate: DropDelegate {
    let item: DashboardWidget
    @Binding var list: [DashboardWidget]
    @Binding var draggingItem: DashboardWidget?
    let onSave: () -> Void
    
    func performDrop(info: DropInfo) -> Bool {
        draggingItem = nil
        onSave()
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggingItem = draggingItem,
              draggingItem.id != item.id,
              let from = list.firstIndex(where: { $0.id == draggingItem.id }),
              let to = list.firstIndex(where: { $0.id == item.id }) else { return }
        
        if list[to].id != draggingItem.id {
            withAnimation(.snappy) {
                list.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

// MARK: - Gallery & Config

struct WidgetGalleryView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    let onAdd: (WidgetType) -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                let theme = viewModel.currentTheme(colorScheme: colorScheme)
                AnimatedGradientBackground(colors: [theme.topColor, theme.bottomColor])
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Add a widget to your dashboard.")
                            .font(.subheadline)
                            .foregroundColor(theme.textColor.opacity(0.7))
                            .padding(.horizontal)
                        
                        ForEach(WidgetType.allCases) { type in
                            Button {
                                onAdd(type)
                            } label: {
                                HStack(spacing: 16) {
                                    ZStack {
                                        Circle()
                                            .fill(.blue.opacity(0.2))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: type.icon)
                                            .font(.title3)
                                            .foregroundColor(.blue)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(type.rawValue)
                                            .font(.headline)
                                        Text(description(for: type))
                                            .font(.caption)
                                            .foregroundColor(theme.textColor.opacity(0.6))
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.title3)
                                }
                                .padding()
                                .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(0.4)))
                                .foregroundColor(theme.textColor)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Widget Gallery")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                }
            }
        }
    }
    
    private func description(for type: WidgetType) -> String {
        switch type {
        case .hourlyForecast: return "24-hour weather breakdown"
        case .dailyForecast: return "Next 10 days of weather"
        case .deepDetails: return "Customizable grid of weather metrics"
        case .rainSummary: return "Focus on upcoming precipitation"
        case .windSummary: return "Current wind speed and direction"
        case .radar: return "Live weather radar with precipitation overlay"
        case .uvIndex: return "Current UV Index and safety advice"
        case .feelsLike: return "Real Feel temperature analysis"
        case .sunPath: return "Sun position, sunrise, and sunset times"
        case .moonPhase: return "Current moon phase and illumination"
        case .uvIndexCurve: return "Daily UV intensity chart"
        }
    }
}

struct WidgetConfigView: View {
    @State var widget: DashboardWidget
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    let onSave: (DashboardWidget) -> Void
    
    var body: some View {
        NavigationStack {
            ZStack {
                let theme = viewModel.currentTheme(colorScheme: colorScheme)
                AnimatedGradientBackground(colors: [theme.topColor, theme.bottomColor])
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Wind Widget Specific Config
                        if widget.type == .windSummary {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Visual Style")
                                    .font(.subheadline)
                                    .foregroundColor(theme.textColor.opacity(0.7))
                                    .padding(.horizontal)
                                
                                Picker("Style", selection: Binding(
                                    get: { widget.config?["style"] ?? "summary" },
                                    set: { newValue in
                                        if widget.config == nil { widget.config = [:] }
                                        widget.config?["style"] = newValue
                                    }
                                )) {
                                    Text("Summary").tag("summary")
                                    Text("Wind Rose").tag("rose")
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal)
                            }
                        }
                        
                        Text("Select which metrics to display in this Deep Details card.")
                            .font(.subheadline)
                            .foregroundColor(theme.textColor.opacity(0.7))
                            .padding(.horizontal)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignSystem.spacingS) {
                            ForEach(WeatherMetric.allCases) { metric in
                                let isSelected = (widget.visibleMetrics ?? []).contains(metric)
                                Button {
                                    if isSelected {
                                        widget.visibleMetrics?.removeAll { $0 == metric }
                                    } else {
                                        if widget.visibleMetrics == nil { widget.visibleMetrics = [] }
                                        widget.visibleMetrics?.append(metric)
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: metric.icon)
                                        Text(metric.rawValue)
                                            .font(.caption.weight(.medium))
                                        Spacer()
                                        if isSelected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                        }
                                    }
                                    .padding()
                                    .foregroundColor(theme.textColor)
                                    .background(RoundedRectangle(cornerRadius: DesignSystem.radiusS).fill(.ultraThinMaterial.opacity(0.4)))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignSystem.radiusS)
                                            .stroke(isSelected ? Color.green : Color.clear, lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Configure Widget")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(widget)
                        dismiss()
                    }
                    .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}


