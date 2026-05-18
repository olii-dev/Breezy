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
    @State private var editModeSessionID = UUID()
    @AppStorage("Breezy.showEditModeButton") private var showEditModeButton = true
    @State private var draggingWidget: DashboardWidget?
    @State private var isInteractingWithChart = false
    @State private var showShareCard = false
    @State private var showingWidgetGallery = false
    @State private var configuringWidget: DashboardWidget?
    @State private var pendingWidgetRemoval: DashboardWidget?


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
                    let useGPS = UserDefaults.standard.bool(forKey: "Breezy.shouldFollowGPS")
                    if useGPS, let location = newLocation {
                        Task { await viewModel.fetchWeather(for: location, isManualRefresh: false) }
                    }
                }
                .onChange(of: locationHelper.significantLocationChange) { oldValue, newLocation in
                    // Auto-refresh on significant location changes (only if using GPS)
                    let useGPS = UserDefaults.standard.bool(forKey: "Breezy.shouldFollowGPS")
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
                                HapticsManager.shared.impact(style: .light)
                                showingWidgetGallery = true
                            } label: {
                                Image(systemName: "plus")
                                    .fontWeight(.bold)
                                    .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                                    .padding(8)
                                    .background(Circle().fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
                            }
                        } else {
                            Button(action: {
                                HapticsManager.shared.impact(style: .light)
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
                                endDashboardEditing()
                            }
                            .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                            .fontWeight(.bold)
                        } else {
                            let theme = viewModel.currentTheme(colorScheme: colorScheme)
                            HStack(spacing: 12) {
                                Button {
                                    HapticsManager.shared.impact(style: .light)
                                    showShareCard = true
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(theme.textColor)
                                        .frame(width: 36, height: 36)
                                }
                                .accessibilityLabel("Share Weather")
                                
                                Button {
                                    HapticsManager.shared.impact(style: .light)
                                    showingTimeMachine = true
                                } label: {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(theme.textColor)
                                        .frame(width: 36, height: 36)
                                }
                                .accessibilityLabel("Time Machine")
                                
                                Button {
                                    HapticsManager.shared.impact(style: .light)
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
                .sheet(isPresented: $showShareCard) {
                    if let weather = viewModel.weather {
                        ShareWeatherCardView(weather: weather, viewModel: viewModel, colorScheme: colorScheme)
                    }
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
                LazyVStack(spacing: DesignSystem.spacingXL) {
                    Spacer()
                        .frame(height: DesignSystem.spacingS)

                    if let locErr = locationHelper.locationError,
                       viewModel.shouldFollowGPS || viewModel.weather == nil {
                        EmptyStateView(state: .error(locErr)) {
                            showingLocationPicker = true
                        }
                        .padding(.top, 40)
                    }

                    if let weather = viewModel.weather {
                        // Main weather display
                        NewWeatherHeaderView(weather: weather, viewModel: viewModel)

                        if viewModel.isShowingStaleWeather, let lastUpdated = viewModel.lastUpdatedDate {
                            WeatherStatusBanner(
                                lastUpdated: lastUpdated,
                                isStale: viewModel.isShowingStaleWeather,
                                detail: viewModel.staleWeatherMessage,
                                textColor: theme.textColor,
                                glassOpacity: viewModel.glassOpacity
                            )
                            .padding(.horizontal, DesignSystem.spacingM)
                        }

                        if let severeAssessment = viewModel.severeWeatherAssessment {
                            SevereWeatherBanner(
                                assessment: severeAssessment,
                                textColor: theme.textColor,
                                glassOpacity: viewModel.glassOpacity
                            )
                            .padding(.horizontal, DesignSystem.spacingM)
                        }
                        
                        // Render widgets in user-defined order
                        ForEach(dashboardWidgets) { widget in
                            EditableSectionContainer(
                                sectionId: widget.id,
                                editSessionID: editModeSessionID,
                                isEditMode: isEditMode,
                                onRemove: {
                                    HapticsManager.shared.impact(style: .heavy)
                                    pendingWidgetRemoval = widget
                                },
                                onConfigure: widget.type.supportsConfiguration ? {
                                    configuringWidget = widget
                                } : nil,
                                content: {
                                    renderWidget(widget, weather: weather)
                                }
                            )
                            .contentShape(Rectangle()) // Ensure entire area is valid for drag
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 1.25, maximumDistance: 50)
                                    .onEnded { _ in
                                        if !isEditMode {
                                            beginDashboardEditing()
                                        }
                                    }
                            )
                            .onDrag {
                                HapticsManager.shared.impact(style: .light)
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
                }
            }
            .overlay(alignment: .topTrailing) {
                if showEditModeButton && !isEditMode {
                    Button {
                        beginDashboardEditing()
                    } label: {
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.5))
                            .padding(8)
                            .background(Circle().fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 16)
                    .padding(.top, 8)
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
            LongPressGesture(minimumDuration: 1.25, maximumDistance: 50)
                .onEnded { _ in
                    if !isEditMode && !isInteractingWithChart {
                        beginDashboardEditing()
                    }
                }
        )
        .alert("Remove Widget?", isPresented: Binding(
            get: { pendingWidgetRemoval != nil },
            set: { isPresented in
                if !isPresented {
                    pendingWidgetRemoval = nil
                }
            }
        )) {
            Button("Cancel", role: .cancel) {
                pendingWidgetRemoval = nil
            }
            Button("Remove", role: .destructive) {
                HapticsManager.shared.notification(type: .error)
                guard let pendingWidgetRemoval else { return }
                withAnimation {
                    dashboardWidgets.removeAll { $0.id == pendingWidgetRemoval.id }
                    saveDashboard()
                }
                self.pendingWidgetRemoval = nil
            }
        } message: {
            Text("This removes the widget from your dashboard, but you can add it back anytime from the widget gallery.")
        }
    }
    
    // MARK: - Dashboard Rendering Functions

    private func beginDashboardEditing() {
        HapticsManager.shared.impact(style: .heavy)
        draggingWidget = nil
        editModeSessionID = UUID()
        withAnimation(.spring()) {
            isEditMode = true
        }
    }

    private func endDashboardEditing() {
        HapticsManager.shared.selectionChanged()
        draggingWidget = nil
        editModeSessionID = UUID()
        withAnimation(.spring()) {
            isEditMode = false
        }
    }
    
    private func loadDashboard() {
        // Try loading modern DashboardWidgets
        if let data = CloudStorage.shared.data(forKey: "Breezy.DashboardWidgets") {
            if let decoded = try? JSONDecoder().decode([DashboardWidget].self, from: data) {
                // Filter out any widgets that might have invalid types if decoding succeeded but enum changed
                dashboardWidgets = withNarrativeWidgetIfNeeded(decoded)
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
                dashboardWidgets = withNarrativeWidgetIfNeeded(dashboardWidgets)
                saveDashboard()
                UserDefaults.standard.removeObject(forKey: "Breezy.SectionOrder") // Clean up
                return
            }
        }
        
        // Fallback to defaults
        dashboardWidgets = DashboardWidget.defaultDashboard
    }

    private func withNarrativeWidgetIfNeeded(_ widgets: [DashboardWidget]) -> [DashboardWidget] {
        guard !widgets.contains(where: { $0.type == .forecastNarrative }) else { return widgets }

        var updated = widgets
        let insertIndex = (updated.firstIndex(where: { $0.type == .dailyForecast }).map { $0 + 1 }) ?? updated.count
        updated.insert(DashboardWidget(id: UUID(), type: .forecastNarrative), at: insertIndex)
        return updated
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
                viewModel: viewModel,
                rangeHours: Int(widget.config?["rangeHours"] ?? "24") ?? 24,
                density: widget.config?["density"] ?? "regular"
            )
            .padding(.horizontal, DesignSystem.spacingM)
            
        case .dailyForecast:
            NewDailyForecastView(
                forecast: weather.dailyForecast,
                viewModel: viewModel,
                config: widget.config
            )
                .padding(.horizontal, DesignSystem.spacingM)

        case .forecastNarrative:
            ForecastNarrativeWidget(
                weather: weather,
                viewModel: viewModel,
                showsExpandedDetail: widget.config?["style"] != "compact"
            )
                .padding(.horizontal, DesignSystem.spacingM)
            
        case .deepDetails:
            if let metrics = weather.metrics {
                let metricsToUse = widget.visibleMetrics ?? Array(viewModel.visibleMetrics)
                MetricsPillsView(metrics: metrics, weather: weather, viewModel: viewModel, customMetrics: metricsToUse)
                    .padding(.horizontal, DesignSystem.spacingM)
            }
            
        case .rainSummary:
            RainSummaryWidget(weather: weather, viewModel: viewModel, config: widget.config)
                .padding(.horizontal, DesignSystem.spacingM)

        case .rainfallToday:
            RainfallTodayWidget(weather: weather, viewModel: viewModel, config: widget.config)
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
                        .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
                        .overlay(RoundedRectangle(cornerRadius: DesignSystem.radiusL).stroke(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.18), lineWidth: 0.5))
                )
                .shadow(color: Color.black.opacity(0.15), radius: 18, x: 0, y: 10)
                .padding(.horizontal, DesignSystem.spacingM)
            } else {
                WindSummaryWidget(weather: weather, viewModel: viewModel)
                    .padding(.horizontal, DesignSystem.spacingM)
            }
                
        case .radar:
            RadarCardView(viewModel: viewModel, locationHelper: locationHelper)
                .padding(.horizontal, DesignSystem.spacingM)
                
        case .smartStack:
            SmartStackWidget(viewModel: viewModel, weather: weather, widget: widget)
                .padding(.horizontal, DesignSystem.spacingM)
                
        case .uvIndex:
            UVIndexWidget(
                weather: weather,
                viewModel: viewModel,
                style: widget.config?["style"] ?? "standard",
                showsCategory: (widget.config?["showCategory"] ?? "true") == "true"
            )
                .padding(.horizontal, DesignSystem.spacingM)
                
        case .feelsLike:
            FeelsLikeWidget(weather: weather, viewModel: viewModel, config: widget.config)
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
                        textColor: viewModel.currentTheme(colorScheme: colorScheme).textColor,
                        style: widget.config?["style"] ?? "full",
                        showsCountdown: (widget.config?["showCountdown"] ?? "true") == "true"
                    )
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                    .padding(.horizontal)
                }
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                        .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
                        .overlay(RoundedRectangle(cornerRadius: DesignSystem.radiusL).stroke(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.18), lineWidth: 0.5))
                )
                .shadow(color: Color.black.opacity(0.15), radius: 18, x: 0, y: 10)
                .padding(.horizontal, DesignSystem.spacingM)
            }
            
        case .moonPhase:
            if let today = weather.dailyForecast.first, let phase = today.moonPhase {
                let moonCard = MoonPhaseCardView(
                    phase: phase,
                    moonrise: today.moonrise,
                    moonset: today.moonset,
                    style: widget.config?["style"] ?? "full",
                    size: widget.config?["size"] ?? "medium",
                    textColor: viewModel.currentTheme(colorScheme: colorScheme).textColor,
                    glassOpacity: viewModel.glassOpacity,
                    showsDisclosure: !isEditMode
                )
                .padding(.horizontal, DesignSystem.spacingM)

                if isEditMode {
                    moonCard
                } else {
                    NavigationLink(destination: AstronomyDetailView(weather: weather, viewModel: viewModel)) {
                        moonCard
                    }
                    .buttonStyle(.plain)
                }
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
                        colorScheme: colorScheme,
                        rangeHours: Int(widget.config?["rangeHours"] ?? "24") ?? 24,
                        showPeak: (widget.config?["showPeak"] ?? "true") == "true"
                    )
                    .padding(.bottom, 16)
                }
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                        .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
                        .overlay(RoundedRectangle(cornerRadius: DesignSystem.radiusL).stroke(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.18), lineWidth: 0.5))
                )
                .shadow(color: Color.black.opacity(0.15), radius: 18, x: 0, y: 10)
                .padding(.horizontal, DesignSystem.spacingM)
            }

        case .windGraph:
            WindGraphWidget(
                weather: weather,
                viewModel: viewModel,
                hoursWindow: Int(widget.config?["rangeHours"] ?? "24") ?? 24,
                isChartInteracting: $isInteractingWithChart
            )
                .padding(.horizontal, DesignSystem.spacingM)
            
        case .minutePrecipitation:
            RainGraphWidget(
                weather: weather,
                viewModel: viewModel,
                minuteWindow: Int(widget.config?["rangeMinutes"] ?? "60") ?? 60
            )
                .padding(.horizontal, DesignSystem.spacingM)

        case .hourlyTemperatures:
            HourlyTemperaturesWidget(weather: weather, viewModel: viewModel, isChartInteracting: $isInteractingWithChart, config: widget.config)
                .padding(.horizontal, DesignSystem.spacingM)

        case .humidityStrip:
            HumidityStripWidget(
                weather: weather,
                viewModel: viewModel,
                rangeHours: Int(widget.config?["rangeHours"] ?? "24") ?? 24,
                isChartInteracting: $isInteractingWithChart
            )
            .padding(.horizontal, DesignSystem.spacingM)

        case .precipitationTimeline:
            PrecipitationTimelineWidget(weather: weather, viewModel: viewModel, config: widget.config)
                .padding(.horizontal, DesignSystem.spacingM)

        case .visibilityCard:
            VisibilityWidget(weather: weather, viewModel: viewModel, config: widget.config)
                .padding(.horizontal, DesignSystem.spacingM)

        case .cloudCoverCard:
            CloudCoverWidget(weather: weather, viewModel: viewModel, config: widget.config)
                .padding(.horizontal, DesignSystem.spacingM)

        case .windHistory:
            WindHistoryWidget(
                weather: weather,
                viewModel: viewModel,
                rangeHours: Int(widget.config?["rangeHours"] ?? "24") ?? 24,
                isChartInteracting: $isInteractingWithChart
            )
            .padding(.horizontal, DesignSystem.spacingM)
        }
    }
}

struct WeatherStatusBanner: View {
    let lastUpdated: Date
    let isStale: Bool
    let detail: String?
    let textColor: Color
    let glassOpacity: Double

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isStale ? "clock.badge.exclamationmark.fill" : "clock.fill")
                .foregroundColor(isStale ? .orange : textColor.opacity(0.8))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(isStale ? "Showing saved weather" : "Weather updated")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(textColor)

                Text("Updated \(lastUpdated.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundColor(textColor.opacity(0.75))

                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(textColor.opacity(0.68))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                .fill(.ultraThinMaterial.opacity(glassOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                        .stroke((isStale ? Color.orange : textColor).opacity(0.18), lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isStale ? "Showing saved weather" : "Weather updated")
    }
}

struct SevereWeatherBanner: View {
    let assessment: SevereWeatherAssessment
    let textColor: Color
    let glassOpacity: Double

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: assessment.symbol)
                .foregroundColor(.red.opacity(0.9))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(assessment.headline)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(textColor)

                Text(assessment.detail)
                    .font(.caption2)
                    .foregroundColor(textColor.opacity(0.8))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                .fill(.ultraThinMaterial.opacity(glassOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                        .stroke(Color.red.opacity(0.22), lineWidth: 0.7)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Severe weather possible. \(assessment.detail)")
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
                        .font(.system(size: 48))
                        .padding(.bottom, 4)
                        .background(Circle().fill(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.1)).padding(4))
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
    
    private func hourlyChartContent(dataSource: [HourlyForecast], minHour: Int, maxHour: Int, nowHour: Int) -> some View {
        let theme = viewModel.currentTheme(colorScheme: colorScheme)
        
        return Chart(dataSource) { hour in
            // Precipitation Background
            if let precip = hour.precipitationChance {
                BarMark(x: .value("Hour", hour.hourValue), y: .value("Precipitation", precip * 10))
                    .foregroundStyle(DesignSystem.skyBlue.opacity(0.15))
            }

            AreaMark(x: .value("Hour", hour.hourValue), y: .value("Temperature", hour.temperatureRaw))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [Color.white.opacity(0.15), Color.clear]), startPoint: .top, endPoint: .bottom))
            
            LineMark(x: .value("Hour", hour.hourValue), y: .value("Temperature", hour.temperatureRaw))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(theme.textColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            
            if hour.hourValue % 3 == 0 && hour.hourValue != minHour && hour.hourValue != maxHour {
                PointMark(x: .value("Hour", hour.hourValue), y: .value("Temperature", hour.temperatureRaw))
                    .symbolSize(0.1)
                    .foregroundStyle(Color.clear)
            }
            
            if hour.hourValue == selectedHourValue || hour.hourValue == nowHour {
                PointMark(x: .value("Hour", hour.hourValue), y: .value("Temperature", hour.temperatureRaw))
                    .symbolSize(symbolSize(for: hour, selectedHourValue: selectedHourValue))
                    .foregroundStyle(symbolColor(for: hour, selectedHourValue: selectedHourValue, theme: theme))
            }
        }
    }
    
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
                    .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
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

                hourlyChartContent(dataSource: dataSource, minHour: minHour, maxHour: maxHour, nowHour: nowHour)

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
                                Text(format12HourTime(hourInt))
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
                .overlay { chartDragOverlay(dataSource: dataSource) }
            }
        }
        .padding(.top, 8)
    }
    
    private func symbolSize(for hour: HourlyForecast, selectedHourValue: Int?) -> Double {
        return hour.hourValue == selectedHourValue ? 100 : 60
    }
    
    private func symbolColor(for hour: HourlyForecast, selectedHourValue: Int?, theme: WeatherTheme) -> Color {
        return hour.hourValue == selectedHourValue ? Color.yellow : theme.textColor
    }
    
    private func format12HourTime(_ hour: Int) -> String {
        if hour == 0 {
            return "12 AM"
        } else if hour < 12 {
            return "\(hour) AM"
        } else if hour == 12 {
            return "12 PM"
        } else {
            return "\(hour - 12) PM"
        }
    }
    
    private func chartDragOverlay(dataSource: [HourlyForecast]) -> some View {
        GeometryReader { g in
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(chartDragGesture(dataSource: dataSource, geometryWidth: g.size.width))
                .overlay(alignment: .topLeading) {
                    chartTooltipContent(dataSource: dataSource, geometryWidth: g.size.width)
                }
        }
    }
    
    private func chartDragGesture(dataSource: [HourlyForecast], geometryWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isDragging = true
                let localX = value.location.x - 12
                let width = max(1, geometryWidth - 24)
                let ratio = min(max(localX / width, 0), 1)
                let idx = Int(round(ratio * CGFloat(max(dataSource.count - 1, 0))))
                if dataSource.indices.contains(idx) {
                    let newSelVal = dataSource[idx].hourValue
                    if selectedHourValue != newSelVal {
                        selectedHourValue = newSelVal
                        HapticsManager.shared.selectionChanged()
                    }
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
    }
    
    private func chartTooltipContent(dataSource: [HourlyForecast], geometryWidth: CGFloat) -> some View {
        GeometryReader { g in
            if let x = dragX, let selVal = selectedHourValue, let selected = dataSource.first(where: { $0.hourValue == selVal }) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(selected.time)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)

                        if let emoji = selected.emoji {
                            Text(emoji)
                        }
                    }
                    if let condition = selected.condition {
                        Text(condition)
                            .font(.caption2)
                            .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.8))
                    }
                    Text(viewModel.formattedTemperature(selected.temperatureRaw, decimals: 1))
                        .font(.headline)
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)

                    FlowLayout(spacing: 6) {
                        if let precip = selected.precipitationChance {
                            TooltipMetricChip(label: "Rain", value: "\(Int(precip * 100))%")
                        }

                        if let amount = selected.precipitationAmount, amount > 0.05 {
                            TooltipMetricChip(label: "Amount", value: viewModel.formattedPrecipitationAmount(amount))
                        }

                        if let windValue = selected.windSpeed {
                            TooltipMetricChip(label: "Wind", value: windValue)
                        }

                        if let gust = selected.windGust, gust > 0 {
                            TooltipMetricChip(label: "Gust", value: viewModel.formattedWindSpeedValue(gust))
                        }

                        if let humidity = selected.humidity {
                            TooltipMetricChip(label: "Humidity", value: "\(humidity)%")
                        }

                        if let uv = selected.uvIndex, uv > 0 {
                            TooltipMetricChip(label: "UV", value: "\(uv)")
                        }
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                .frame(maxWidth: 220)
                .position(x: min(max(x, 60), geometryWidth - 60), y: 24)
                .transition(.opacity)
            }
        }
    }
    
    private func hourlyTemperatureChartContent() -> some View {
        let dataSource = (allHourlyData?.isEmpty == false) ? (allHourlyData!) : hourlyData
        let minHour = dataSource.map { $0.hourValue }.min() ?? 0
        let maxHour = dataSource.map { $0.hourValue }.max() ?? 23
        let nowHour = Calendar.current.component(.hour, from: Date())
        let theme = viewModel.currentTheme(colorScheme: colorScheme)
        
        return Chart(dataSource) { hour in
            AreaMark(x: .value("Hour", hour.hourValue), y: .value("Temperature", hour.temperatureRaw))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(gradient: Gradient(colors: [Color.white.opacity(0.15), Color.clear]), startPoint: .top, endPoint: .bottom))
            
            LineMark(x: .value("Hour", hour.hourValue), y: .value("Temperature", hour.temperatureRaw))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(theme.textColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            
            if hour.hourValue % 3 == 0 && hour.hourValue != minHour && hour.hourValue != maxHour {
                PointMark(x: .value("Hour", hour.hourValue), y: .value("Temperature", hour.temperatureRaw))
                    .symbolSize(0.1)
                    .foregroundStyle(Color.clear)
            }
            
            if hour.hourValue == selectedHourValue || hour.hourValue == nowHour {
                PointMark(x: .value("Hour", hour.hourValue), y: .value("Temperature", hour.temperatureRaw))
                    .symbolSize(symbolSize(for: hour, selectedHourValue: selectedHourValue))
                    .foregroundStyle(symbolColor(for: hour, selectedHourValue: selectedHourValue, theme: theme))
            }
        }
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
                    Text(hour.emoji ?? "☁️")
                        .font(.system(size: 80))
                    
                    Text(hour.time)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                    
                    Text(viewModel.formattedTemperature(hour.temperatureRaw))
                        .font(.system(size: 64, weight: .light))
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                    
                    Text(hour.condition ?? "Unknown")
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

    private var forecastRows: [(index: Int, day: DailyForecast)] {
        Array(forecast.enumerated()).map { (index: $0.offset, day: $0.element) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("10-Day Forecast")
                .font(.title3.weight(.semibold))
                .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                .padding(.horizontal)
            
            VStack(spacing: 8) {
                ForEach(forecastRows, id: \.index) { row in
                    NavigationLink(destination: DailyForecastDetailView(day: row.day, viewModel: viewModel).id("\(row.day.id)-\(row.index)")) {
                        DailyForecastRowView(day: row.day, viewModel: viewModel)
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
                    .background(Circle().fill(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.1)).padding(2))
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
                                textColor: viewModel.currentTheme(colorScheme: colorScheme).textColor,
                                viewModel: viewModel
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
    @ObservedObject var viewModel: WeatherViewModel
    
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
                    .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
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
                        .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
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
    let rangeHours: Int
    let density: String
    @Environment(\.colorScheme) var colorScheme

    private var tileWidth: CGFloat {
        density == "compact" ? 52 : 60
    }

    private var tileSpacing: CGFloat {
        density == "compact" ? DesignSystem.spacingXS : DesignSystem.spacingS
    }

    private var titleText: String {
        let hoursToShow = allHourlyData ?? hourlyData
        let displayed = min(rangeHours, hoursToShow.count)
        return "\(displayed)-Hour Forecast"
    }

    private var displayedHours: [HourlyForecast] {
        let source = allHourlyData ?? hourlyData
        let displayedCount = rangeHours > 0 ? min(rangeHours, source.count) : source.count
        return Array(source.prefix(displayedCount))
    }
    
    // Find the index of the current hour (or closest hour)
    private var currentHourIndex: Int {
        let currentHour = Calendar.current.component(.hour, from: Date())
        let dataToUse = displayedHours
        
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
            Label(titleText, systemImage: "chart.xyaxis.line")
                .font(.caption.weight(.bold))
                .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.6))

            if displayedHours.isEmpty {
                Text("Hourly forecast unavailable right now.")
                    .font(.caption)
                    .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.72))
                    .padding(.top, 4)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: tileSpacing) {
                            let theme = viewModel.currentTheme(colorScheme: colorScheme)

                            ForEach(Array(displayedHours.enumerated()), id: \.offset) { index, hour in
                                VStack(spacing: 8) {
                                    Text(hour.time)
                                        .font(.caption.weight(index == currentHourIndex ? .bold : .medium))
                                        .foregroundColor(theme.textColor.opacity(index == currentHourIndex ? 1.0 : 0.75))

                                    if viewModel.useMinimalistIcons {
                                        Image(systemName: viewModel.weatherIcon(for: hour.condition ?? "cloud"))
                                            .font(.title3)
                                            .foregroundColor(theme.textColor)
                                            .symbolRenderingMode(.hierarchical)
                                            .frame(height: 28)
                                    } else {
                                        Text(hour.emoji ?? "☁️")
                                            .font(.title3)
                                            .frame(height: 28)
                                            .background(Circle().fill(theme.textColor.opacity(0.1)).padding(2))
                                    }

                                    Text(viewModel.formattedTemperature(hour.temperatureRaw))
                                        .font(.body.weight(index == currentHourIndex ? .bold : .semibold))
                                        .foregroundColor(theme.textColor)
                                }
                                .frame(width: tileWidth)
                                .id(index)
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
                        scrollToCurrentHour(proxy: proxy, hourCount: displayedHours.count)
                    }
                    .onChange(of: displayedHours.count) { _, newCount in
                        scrollToCurrentHour(proxy: proxy, hourCount: newCount)
                    }
                }
            }
        }
        .softGlassCard(padding: DesignSystem.spacingM, cornerRadius: DesignSystem.radiusM)
    }
    
    private func scrollToCurrentHour(proxy: ScrollViewProxy, hourCount: Int) {
        guard hourCount > 0 else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let anchor: UnitPoint
            if currentHourIndex <= 1 {
                anchor = .leading
            } else if currentHourIndex >= max(0, hourCount - 2) {
                anchor = .trailing
            } else {
                anchor = .center
            }

            withAnimation(.easeInOut(duration: 0.8)) {
                proxy.scrollTo(currentHourIndex, anchor: anchor)
            }
        }
    }
}

struct MoonPhaseCardView: View {
    let phase: MoonPhase
    let moonrise: String?
    let moonset: String?
    let style: String
    let size: String
    let textColor: Color
    let glassOpacity: Double
    let showsDisclosure: Bool

    private var moonSize: CGFloat {
        switch size {
        case "small": return 54
        case "large": return 92
        default: return 70
        }
    }

    private var isCompact: Bool {
        style == "compact"
    }

    private var illuminationText: String {
        "Illumination \(Int((phase.illumination * 100).rounded()))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Label("Moon Phase", systemImage: "moon.stars.fill")
                    .font(.caption.weight(.bold))
                    .foregroundColor(textColor.opacity(0.6))

                Spacer()

                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundColor(textColor.opacity(0.45))
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)

            if isCompact {
                HStack(spacing: 16) {
                    MoonPhaseView2(
                        phase: phase,
                        size: moonSize,
                        color: textColor
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text(phase.phase)
                            .font(.headline)
                            .foregroundColor(textColor)

                        Text(illuminationText)
                            .font(.caption)
                            .foregroundColor(textColor.opacity(0.72))

                        if let eventSummary {
                            Text(eventSummary)
                                .font(.caption)
                                .foregroundColor(textColor.opacity(0.72))
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                }
                .padding(20)
            } else {
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        MoonPhaseView2(
                            phase: phase,
                            size: moonSize,
                            color: textColor
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(phase.phase)
                                .font(.headline)
                                .foregroundColor(textColor)

                            Text(illuminationText)
                                .font(.caption)
                                .foregroundColor(textColor.opacity(0.72))

                            if let eventSummary {
                                Text(eventSummary)
                                    .font(.caption2)
                                    .foregroundColor(textColor.opacity(0.68))
                                    .lineLimit(2)
                            }
                        }
                    }

                    Divider()
                        .frame(height: 88)
                        .background(textColor.opacity(0.2))

                    VStack(alignment: .leading, spacing: 14) {
                        if let rise = moonrise {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(textColor.opacity(0.6))
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("Moonrise").font(.caption2).opacity(0.7)
                                    Text(rise).font(.subheadline.bold())
                                }
                            }
                        }
                        if let set = moonset {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(textColor.opacity(0.6))
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("Moonset").font(.caption2).opacity(0.7)
                                    Text(set).font(.subheadline.bold())
                                }
                            }
                        }
                    }
                    .foregroundColor(textColor)

                    Spacer()
                }
                .padding(20)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                .fill(.ultraThinMaterial.opacity(glassOpacity))
                .overlay(RoundedRectangle(cornerRadius: DesignSystem.radiusL).stroke(textColor.opacity(0.18), lineWidth: 0.5))
        )
        .shadow(color: Color.black.opacity(0.15), radius: 18, x: 0, y: 10)
    }

    private var eventSummary: String? {
        switch (moonrise, moonset) {
        case let (rise?, set?):
            return "Rise \(rise) · Set \(set)"
        case let (rise?, nil):
            return "Rise \(rise)"
        case let (nil, set?):
            return "Set \(set)"
        default:
            return nil
        }
    }
}

struct HourlyInsightPill: View {
    let icon: String
    let title: String
    let value: String
    let textColor: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                Text(value)
                    .font(.caption.weight(.medium))
            }
        }
        .foregroundColor(textColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.12))
        )
    }
}

struct HourlyForecastStripTile: View {
    let hour: HourlyForecast
    let isCurrent: Bool
    @ObservedObject var viewModel: WeatherViewModel
    let textColor: Color

    private var chanceLabel: String? {
        guard let precipitationChance = hour.precipitationChance, precipitationChance >= 0.2 else { return nil }
        return "\(Int(precipitationChance * 100))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(hour.time)
                .font(.caption.weight(isCurrent ? .bold : .medium))
                .foregroundColor(textColor.opacity(isCurrent ? 1 : 0.74))

            Group {
                if viewModel.useMinimalistIcons {
                    Image(systemName: viewModel.weatherIcon(for: hour.condition ?? "cloud"))
                        .font(.title3)
                        .foregroundColor(textColor)
                        .symbolRenderingMode(.hierarchical)
                } else {
                    Text(hour.emoji ?? "☁️")
                        .font(.title3)
                }
            }
            .frame(height: 28)

            Text(viewModel.formattedTemperature(hour.temperatureRaw))
                .font(.body.weight(isCurrent ? .bold : .semibold))
                .foregroundColor(textColor)

            Text(hour.condition ?? "Forecast")
                .font(.caption2)
                .foregroundColor(textColor.opacity(0.68))
                .lineLimit(2)
                .frame(height: 28, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 6) {
                if let chanceLabel {
                    Label(chanceLabel, systemImage: "drop.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(DesignSystem.skyBlue)
                }

                if let windSpeed = hour.windSpeed {
                    Label(windSpeed, systemImage: "wind")
                        .font(.caption2)
                        .foregroundColor(textColor.opacity(0.7))
                        .lineLimit(1)
                }
            }
        }
        .frame(width: 104, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusS)
                .fill(isCurrent ? Color.white.opacity(0.2) : Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusS)
                        .stroke(textColor.opacity(isCurrent ? 0.28 : 0.12), lineWidth: 0.8)
                )
        )
    }
}

struct NewDailyForecastView: View {
    let forecast: [DailyForecast]
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    var config: [String: String]?

    private var forecastRows: [(index: Int, day: DailyForecast)] {
        Array(displayedForecast.enumerated()).map { (index: $0.offset, day: $0.element) }
    }

    private var rangeDays: Int {
        max(1, Int(config?["rangeDays"] ?? "10") ?? 10)
    }

    private var showIcons: Bool {
        (config?["showIcons"] ?? "true") == "true"
    }

    private var displayedForecast: [DailyForecast] {
        Array(forecast.prefix(rangeDays))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(rangeDays)-Day Forecast", systemImage: "calendar")
                .font(.caption.weight(.bold))
                .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.6))
            
            VStack(spacing: DesignSystem.spacingXS) {
                ForEach(forecastRows, id: \.index) { row in
                    NavigationLink(destination: DailyForecastDetailView(day: row.day, viewModel: viewModel).id("\(row.day.id)-\(row.index)")) {
                        SimpleDailyRow(day: row.day, viewModel: viewModel, showIcons: showIcons)
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
    let showIcons: Bool
    
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
            if showIcons {
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
                        .background(Circle().fill(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.1)).padding(2))
                }
            } else {
                Color.clear
                    .frame(width: 30, height: 30)
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
        let columnCount = max(1, min(pills.count, 3))
        let columns = Array(repeating: GridItem(.flexible()), count: columnCount)
        
        LazyVGrid(columns: columns, spacing: DesignSystem.spacingS) {
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
                            .background(Circle().fill(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.1)).padding(1))
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
        
        // Preserve the user's configured order and include only metrics with data.
        for metric in visibleList {
            
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

struct ForecastNarrativeWidget: View {
    let weather: WeatherInfo
    @ObservedObject var viewModel: WeatherViewModel
    let showsExpandedDetail: Bool
    @Environment(\.colorScheme) var colorScheme

    private var narrative: WeatherViewModel.ForecastNarrativeSummary {
        viewModel.forecastNarrativeSummary ?? .init(
            headline: "Mostly steady weather through the next few days.",
            detail: "No single rain, wind, or temperature swing dominates the outlook right now."
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Forecast Story", systemImage: "text.justify.left")
                .font(.caption.weight(.bold))
                .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.6))

            Text(narrative.headline)
                .font(.headline)
                .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                .fixedSize(horizontal: false, vertical: true)

            if showsExpandedDetail, let detail = narrative.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }


        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softGlassCard()
    }
}

struct HourlyTemperaturesWidget: View {
    let weather: WeatherInfo
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedHourID: String? = nil
    var isChartInteracting: Binding<Bool>? = nil
    var config: [String: String]?

    private var rangeHours: Int { Int(config?["rangeHours"] ?? "0") ?? 0 }

    private var hours: [HourlyForecast] {
        let all = weather.allHourlyData ?? weather.hourlyForecast
        if rangeHours > 0 {
            return Array(all.prefix(rangeHours))
        }
        return all
    }

    var body: some View {
        let theme = viewModel.currentTheme(colorScheme: colorScheme)
        VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
            Label("Hourly Temperatures", systemImage: "thermometer.sun.fill")
                .font(.caption.weight(.bold))
                .foregroundColor(theme.textColor.opacity(0.6))
                .padding(.horizontal)
                .padding(.top, 16)

            if hours.isEmpty {
                Text("No hourly data available.")
                    .font(.caption)
                    .foregroundColor(theme.textColor.opacity(0.6))
                    .padding(.horizontal)
                    .padding(.bottom, 16)
            } else {
                hourlyChart(theme: theme)
                    .frame(height: 160)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                        .stroke(theme.textColor.opacity(0.18), lineWidth: 0.5)
                )
        )
        .shadow(color: Color.black.opacity(0.15), radius: 18, x: 0, y: 10)
    }

    @ViewBuilder
    private func hourlyChart(theme: WeatherTheme) -> some View {
        let interpolation: InterpolationMethod = hours.count >= 4 ? .catmullRom : .linear
        let temps = hours.map(\.temperatureRaw)
        let minTemp = temps.min() ?? 0
        let maxTemp = temps.max() ?? 100
        let padding = max(2, (maxTemp - minTemp) * 0.15)
        let range = (minTemp - padding)...(maxTemp + padding)
        let stride = hours.count <= 6 ? 1 : hours.count <= 12 ? 2 : 3
        let labelHourValues: [Int] = {
            let values = hours.map(\.hourValue)
            return values.enumerated().compactMap { index, v in
                (index == 0 || index == values.count - 1 || index % stride == 0) ? v : nil
            }
        }()

        Chart {
            ForEach(hours) { hour in
                AreaMark(
                    x: .value("Hour", hour.hourValue),
                    yStart: .value("Baseline", range.lowerBound),
                    yEnd: .value("Temperature", hour.temperatureRaw)
                )
                .interpolationMethod(interpolation)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Hour", hour.hourValue),
                    y: .value("Temperature", hour.temperatureRaw)
                )
                .interpolationMethod(interpolation)
                .foregroundStyle(Color.white.opacity(0.96))
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }

            if let selID = selectedHourID, let hour = hours.first(where: { $0.id == selID }) {
                RuleMark(x: .value("Selected", Double(hour.hourValue)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
                    .foregroundStyle(theme.textColor.opacity(0.35))
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(viewModel.formattedTemperature(hour.temperatureRaw))
                                .font(.caption.weight(.bold))
                                .foregroundColor(theme.textColor)
                            Text(hour.time)
                                .font(.caption2.weight(.medium))
                                .foregroundColor(theme.textColor.opacity(0.72))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.textColor.opacity(0.1), lineWidth: 0.5))
                    }
            }
        }
        .chartXScale(domain: (hours.first?.hourValue ?? 0)...(hours.last?.hourValue ?? 23))
        .chartYScale(domain: range)
        .chartXAxis {
            AxisMarks(values: labelHourValues) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                    .foregroundStyle(theme.textColor.opacity(0.12))
                AxisValueLabel {
                    if let hour = value.as(Int.self), let match = hours.first(where: { $0.hourValue == hour }) {
                        Text(match.time)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(theme.textColor.opacity(0.72))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                    .foregroundStyle(theme.textColor.opacity(0.12))
                AxisValueLabel {
                    if let temp = value.as(Double.self) {
                        Text(viewModel.formattedTemperature(temp))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(theme.textColor.opacity(0.72))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isChartInteracting?.wrappedValue = true
                                guard let plotFrame = proxy.plotFrame else { return }
                                let origin = geometry[plotFrame].origin
                                let locationX = value.location.x - origin.x
                                if let hourInt: Int = proxy.value(atX: locationX) {
                                    let nearest = hours.min { abs($0.hourValue - hourInt) < abs($1.hourValue - hourInt) }
                                    if nearest?.id != selectedHourID {
                                        HapticsManager.shared.impact(style: .light)
                                    }
                                    selectedHourID = nearest?.id
                                }
                            }
                            .onEnded { _ in
                                isChartInteracting?.wrappedValue = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    selectedHourID = nil
                                }
                            }
                    )
            }
        }
    }
}

struct RainSummaryWidget: View {
    let weather: WeatherInfo
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    var config: [String: String]?
    
    private var style: String { config?["style"] ?? "standard" }

    var body: some View {
        let textColor = viewModel.currentTheme(colorScheme: colorScheme).textColor
        VStack(alignment: .leading, spacing: 10) {
            Label("Precipitation", systemImage: "cloud.rain.fill")
                .font(.caption.weight(.bold))
                .foregroundColor(textColor.opacity(0.6))
            
            VStack(alignment: .leading, spacing: 12) {
                if let soon = viewModel.rainSoonLabel {
                    Text(soon)
                        .font(.headline)
                        .foregroundColor(textColor)

                    if style != "compact", let detail = viewModel.rainSoonDetail {
                        Text(detail)
                            .font(.caption)
                            .foregroundColor(textColor.opacity(0.72))
                    }
                } else {
                    Text("No rain expected soon")
                        .font(.subheadline)
                        .foregroundColor(textColor.opacity(0.7))
                }
                
                if let today = weather.dailyForecast.first {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading) {
                            Text(today.chanceOfRain ?? "0%")
                                .font(.title3.weight(.bold))
                                .foregroundColor(textColor)
                            Text("Chance")
                                .font(.caption2)
                                .foregroundColor(textColor.opacity(0.6))
                        }
                        
                        if style != "compact", let rainfall = weather.metrics?.todayRainfall {
                            VStack(alignment: .leading) {
                                Text(rainfall)
                                    .font(.title3.weight(.bold))
                                    .foregroundColor(textColor)
                                Text("Today total")
                                    .font(.caption2)
                                    .foregroundColor(textColor.opacity(0.6))
                            }
                        }

                        if style == "detailed", let intensity = weather.metrics?.todayMaxRainIntensity {
                            VStack(alignment: .leading) {
                                Text(intensity)
                                    .font(.title3.weight(.bold))
                                    .foregroundColor(textColor)
                                Text("Peak rate")
                                    .font(.caption2)
                                    .foregroundColor(textColor.opacity(0.6))
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

struct RainfallTodayWidget: View {
    let weather: WeatherInfo
    @ObservedObject var viewModel: WeatherViewModel
    var config: [String: String]?
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedHourID: String? = nil
    @State private var isDragging: Bool = false
    
    private var style: String { config?["style"] ?? "standard" }

    private var todayChance: String {
        weather.dailyForecast.first?.chanceOfRain ?? "0%"
    }

    private var totalRainfall: String {
        weather.metrics?.todayRainfall ?? "0 \(viewModel.precipitationUnit.symbol)"
    }

    private var peakIntensity: String {
        weather.metrics?.todayMaxRainIntensity ?? "No heavy bursts"
    }

    var body: some View {
        let textColor = viewModel.currentTheme(colorScheme: colorScheme).textColor

        VStack(alignment: .leading, spacing: 12) {
            Label("Rainfall Today", systemImage: "drop.fill")
                .font(.caption.weight(.bold))
                .foregroundColor(textColor.opacity(0.6))

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(totalRainfall)
                        .font(.system(size: 30, weight: .semibold, design: viewModel.typography.design))
                        .foregroundColor(textColor)
                    Text("Accumulated so far today")
                        .font(.caption)
                        .foregroundColor(textColor.opacity(0.68))
                }

                Spacer(minLength: 0)

                Text(todayChance)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(textColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                    )
            }

            if style != "minimal" {
                HStack(spacing: 12) {
                    WeatherStatBlock(title: "Peak rate", value: peakIntensity, textColor: textColor)
                    WeatherStatBlock(title: "Rain chance", value: todayChance, textColor: textColor)
                }
            }

            if style != "minimal", let rainDetail = viewModel.rainSoonDetail, let rainHeadline = viewModel.rainSoonLabel {
                VStack(alignment: .leading, spacing: 3) {
                    Text(rainHeadline)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(textColor)
                    Text(rainDetail)
                        .font(.caption2)
                        .foregroundColor(textColor.opacity(0.68))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softGlassCard()
    }
}

struct RainGraphWidget: View {
    let weather: WeatherInfo
    @ObservedObject var viewModel: WeatherViewModel
    let minuteWindow: Int
    @Environment(\.colorScheme) var colorScheme

    private var minuteForecast: [MinuteForecast] {
        Array((weather.metrics?.minuteForecast ?? []).prefix(minuteWindow))
    }

    private var peakMinuteSummary: String? {
        guard let peak = minuteForecast.enumerated().max(by: { $0.element.precipitationChance < $1.element.precipitationChance }) else {
            return nil
        }

        let chance = Int(peak.element.precipitationChance * 100)
        guard chance > 0 else { return nil }
        return "Peak chance reaches \(chance)% in about \(peak.offset) min."
    }

    var body: some View {
        let textColor = viewModel.currentTheme(colorScheme: colorScheme).textColor

        VStack(alignment: .leading, spacing: 12) {
            Label("Rain Graph", systemImage: "chart.bar.fill")
                .font(.caption.weight(.bold))
                .foregroundColor(textColor.opacity(0.6))

            if let rainHeadline = viewModel.rainSoonLabel {
                Text(rainHeadline)
                    .font(.headline)
                    .foregroundColor(textColor)
            } else {
                Text("Next \(minuteWindow) minutes")
                    .font(.headline)
                    .foregroundColor(textColor)
            }

            if let peakMinuteSummary {
                Text(peakMinuteSummary)
                    .font(.caption)
                    .foregroundColor(textColor.opacity(0.72))
            } else {
                Text("No stronger rain signal stands out across the next hour right now.")
                    .font(.caption)
                    .foregroundColor(textColor.opacity(0.72))
            }

            MinutePrecipitationChartView(minuteData: minuteForecast, textColor: textColor, maxMinutes: minuteWindow)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softGlassCard()
    }
}

struct WindGraphWidget: View {
    private struct WindPoint: Identifiable {
        let id = UUID()
        let index: Int
        let time: String
        let speed: Double
    }

    let weather: WeatherInfo
    @ObservedObject var viewModel: WeatherViewModel
    let hoursWindow: Int
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedWindIndex: Int?
    var isChartInteracting: Binding<Bool>? = nil

    private var windPoints: [WindPoint] {
        Array((weather.allHourlyData ?? weather.hourlyForecast).prefix(hoursWindow).enumerated()).compactMap { index, hour in
            guard let speed = numericWindSpeed(from: hour.windSpeed) else { return nil }
            return WindPoint(index: index, time: hour.time, speed: speed)
        }
    }

    private var peakWindPoint: WindPoint? {
        windPoints.max(by: { $0.speed < $1.speed })
    }

    private var selectedWindPoint: WindPoint? {
        guard let selectedWindIndex, windPoints.indices.contains(selectedWindIndex) else { return nil }
        return windPoints[selectedWindIndex]
    }

    var body: some View {
        let textColor = viewModel.currentTheme(colorScheme: colorScheme).textColor

        VStack(alignment: .leading, spacing: 12) {
            Label("Wind Graph", systemImage: "chart.line.uptrend.xyaxis")
                .font(.caption.weight(.bold))
                .foregroundColor(textColor.opacity(0.6))

            if let peakWindPoint {
                Text("Breeziest stretch is around \(peakWindPoint.time)")
                    .font(.headline)
                    .foregroundColor(textColor)

                Text("Peak wind reaches about \(viewModel.formattedWindSpeedValue(peakWindPoint.speed)) across the next \(hoursWindow) hours.")
                    .font(.caption)
                    .foregroundColor(textColor.opacity(0.72))
            } else {
                Text("Wind trend")
                    .font(.headline)
                    .foregroundColor(textColor)

                Text("Hourly wind data is not available for this forecast.")
                    .font(.caption)
                    .foregroundColor(textColor.opacity(0.72))
            }

            if windPoints.isEmpty {
                Text("No hourly wind speeds available right now.")
                    .font(.caption)
                    .foregroundColor(textColor.opacity(0.6))
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.radiusS)
                            .fill(Color.white.opacity(0.06))
                    )
            } else {
                Chart {
                    ForEach(windPoints) { point in
                        AreaMark(
                            x: .value("Hour", point.index),
                            y: .value("Wind", point.speed)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [DesignSystem.skyBlue.opacity(0.35), DesignSystem.skyBlue.opacity(0.04)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Hour", point.index),
                            y: .value("Wind", point.speed)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(DesignSystem.skyBlue)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                    }

                    if let peakWindPoint {
                        PointMark(
                            x: .value("Peak Hour", peakWindPoint.index),
                            y: .value("Peak Wind", peakWindPoint.speed)
                        )
                        .symbolSize(90)
                        .foregroundStyle(textColor)
                    }

                    if let selectedWindPoint {
                        RuleMark(x: .value("Selected Hour", selectedWindPoint.index))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
                            .foregroundStyle(textColor.opacity(0.35))
                            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(selectedWindPoint.time)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(textColor)
                                    Text(viewModel.formattedWindSpeedValue(selectedWindPoint.speed))
                                        .font(.headline)
                                        .foregroundColor(textColor)
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(textColor.opacity(0.12), lineWidth: 0.5))
                            }

                        PointMark(
                            x: .value("Selected Point", selectedWindPoint.index),
                            y: .value("Selected Speed", selectedWindPoint.speed)
                        )
                        .symbolSize(110)
                        .foregroundStyle(textColor)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: 6)) { value in
                        AxisValueLabel {
                            if let index = value.as(Int.self), windPoints.indices.contains(index) {
                                Text(windPoints[index].time)
                                    .font(.system(size: 10))
                                    .foregroundColor(textColor.opacity(0.6))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                            .foregroundStyle(textColor.opacity(0.15))
                        AxisValueLabel {
                            if let speed = value.as(Double.self) {
                                Text(viewModel.formattedWindSpeedValue(speed))
                                    .font(.system(size: 10))
                                    .foregroundColor(textColor.opacity(0.6))
                            }
                        }
                    }
                }
                .chartYScale(domain: 0...(max((peakWindPoint?.speed ?? 0) * 1.2, 8)))
                .frame(height: 170)
                .padding(.top, 4)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        isChartInteracting?.wrappedValue = true
                                        guard let plotFrame = proxy.plotFrame else { return }
                                        let origin = geometry[plotFrame].origin
                                        let location = CGPoint(x: value.location.x - origin.x, y: value.location.y - origin.y)
                                        if let index: Int = proxy.value(atX: location.x),
                                           let snappedIndex = windPoints.firstIndex(where: { $0.index == index }) {
                                            if snappedIndex != selectedWindIndex {
                                                HapticsManager.shared.impact(style: .light)
                                            }
                                            selectedWindIndex = snappedIndex
                                        }
                                    }
                                    .onEnded { _ in
                                        isChartInteracting?.wrappedValue = false
                                        selectedWindIndex = nil
                                    }
                            )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softGlassCard()
    }

    private func numericWindSpeed(from windString: String?) -> Double? {
        guard let windString else { return nil }
        let cleaned = windString.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        return Double(cleaned)
    }
}

// MARK: - Humidity Strip Widget

struct HumidityStripWidget: View {
    let weather: WeatherInfo
    @ObservedObject var viewModel: WeatherViewModel
    let rangeHours: Int
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedHourID: String? = nil
    var isChartInteracting: Binding<Bool>? = nil

    private var hours: [HourlyForecast] {
        Array((weather.allHourlyData ?? weather.hourlyForecast).prefix(rangeHours))
            .filter { $0.humidity != nil }
    }

    var body: some View {
        let theme = viewModel.currentTheme(colorScheme: colorScheme)
        let textColor = theme.textColor
        VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
            Label("Humidity", systemImage: "humidity.fill")
                .font(.caption.weight(.bold))
                .foregroundColor(textColor.opacity(0.6))
                .padding(.horizontal)
                .padding(.top, 16)

            if hours.isEmpty {
                Text("Humidity data unavailable.")
                    .font(.caption)
                    .foregroundColor(textColor.opacity(0.6))
                    .padding(.horizontal)
                    .padding(.bottom, 16)
            } else {
                let stride = hours.count <= 6 ? 1 : hours.count <= 12 ? 2 : 3
                let labelHourValues: [Int] = hours.map(\.hourValue).enumerated().compactMap { i, v in
                    (i == 0 || i == hours.count - 1 || i % stride == 0) ? v : nil
                }
                let interpolation: InterpolationMethod = hours.count >= 4 ? .catmullRom : .linear
                let selectedHour = selectedHourID.flatMap { id in hours.first { $0.id == id } }

                Chart {
                    ForEach(hours) { hour in
                        AreaMark(
                            x: .value("Hour", hour.hourValue),
                            yStart: .value("Base", 0),
                            yEnd: .value("Humidity", Double(hour.humidity ?? 0))
                        )
                        .interpolationMethod(interpolation)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [DesignSystem.skyBlue.opacity(0.35), DesignSystem.skyBlue.opacity(0.04)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Hour", hour.hourValue),
                            y: .value("Humidity", Double(hour.humidity ?? 0))
                        )
                        .interpolationMethod(interpolation)
                        .foregroundStyle(DesignSystem.skyBlue)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    }

                    if let sel = selectedHour {
                        RuleMark(x: .value("Selected", sel.hourValue))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(textColor.opacity(0.35))
                            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(sel.humidity ?? 0)%")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(textColor)
                                    Text(sel.time)
                                        .font(.caption2.weight(.medium))
                                        .foregroundColor(textColor.opacity(0.72))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(textColor.opacity(0.1), lineWidth: 0.5))
                            }
                    }
                }
                .chartXScale(domain: (hours.first?.hourValue ?? 0)...(hours.last?.hourValue ?? 23))
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: labelHourValues) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                            .foregroundStyle(textColor.opacity(0.12))
                        AxisValueLabel {
                            if let h = value.as(Int.self), let match = hours.first(where: { $0.hourValue == h }) {
                                Text(match.time)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(textColor.opacity(0.72))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                            .foregroundStyle(textColor.opacity(0.12))
                        AxisValueLabel {
                            if let pct = value.as(Int.self) {
                                Text("\(pct)%")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(textColor.opacity(0.72))
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        isChartInteracting?.wrappedValue = true
                                        guard let plotFrame = proxy.plotFrame else { return }
                                        let locationX = value.location.x - geometry[plotFrame].origin.x
                                        if let hourInt: Int = proxy.value(atX: locationX) {
                                            let nearest = hours.min { abs($0.hourValue - hourInt) < abs($1.hourValue - hourInt) }
                                            if nearest?.id != selectedHourID {
                                                HapticsManager.shared.impact(style: .light)
                                            }
                                            selectedHourID = nearest?.id
                                        }
                                    }
                                    .onEnded { _ in
                                        isChartInteracting?.wrappedValue = false
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                            selectedHourID = nil
                                        }
                                    }
                            )
                    }
                }

                .frame(height: 160)
                .padding(.horizontal, 12)
                 .padding(.bottom, 16)
             }
         }
        .softGlassCard()
        .shadow(color: .black.opacity(0.15), radius: 18, x: 0, y: 10)
    }
}

// MARK: - Precipitation Timeline Widget

struct PrecipitationTimelineWidget: View {
    let weather: WeatherInfo
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    var config: [String: String]?

    private struct DayRain: Identifiable {
        let id: String
        let shortName: String
        let chance: Int
    }

    private var days: [DayRain] {
        let limit = Int(config?["rangeDays"] ?? "0") ?? 0
        let forecast = limit > 0 ? Array(weather.dailyForecast.prefix(limit)) : weather.dailyForecast
        var seen = Set<String>()
        return forecast.compactMap { day in
            let raw = day.chanceOfRain ?? "0"
            let numeric = Int(raw.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
            let short = String(day.dayName.prefix(3))
            guard !seen.contains(short) else { return nil }
            seen.insert(short)
            return DayRain(id: day.id, shortName: short, chance: numeric)
        }
    }

    var body: some View {
        let theme = viewModel.currentTheme(colorScheme: colorScheme)
        let textColor = theme.textColor

        VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
            Label("Precipitation Forecast", systemImage: "chart.bar.xaxis")
                .font(.caption.weight(.bold))
                .foregroundColor(textColor.opacity(0.6))
                .padding(.horizontal)
                .padding(.top, 16)

            if days.isEmpty {
                Text("No forecast data.")
                    .font(.caption)
                    .foregroundColor(textColor.opacity(0.6))
                    .padding(.horizontal)
                    .padding(.bottom, 16)
            } else {
                Chart {
                    ForEach(days) { day in
                        BarMark(
                            x: .value("Day", day.shortName),
                            y: .value("Chance", day.chance)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [DesignSystem.skyBlue.opacity(0.85), DesignSystem.skyBlue.opacity(0.5)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .cornerRadius(6)
                        .annotation(position: .top) {
                            Text(day.chance > 0 ? "\(day.chance)%" : "")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(textColor.opacity(0.75))
                        }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                            .foregroundStyle(textColor.opacity(0.12))
                        AxisValueLabel {
                            if let pct = value.as(Int.self) {
                                Text("\(pct)%")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(textColor.opacity(0.65))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let name = value.as(String.self) {
                                Text(name)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(textColor.opacity(0.72))
                            }
                        }
                    }
                }
                .frame(height: 160)
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
                .overlay(RoundedRectangle(cornerRadius: DesignSystem.radiusL).stroke(textColor.opacity(0.18), lineWidth: 0.5))
        )
        .shadow(color: .black.opacity(0.15), radius: 18, x: 0, y: 10)
    }
}

// MARK: - Visibility Widget

struct VisibilityWidget: View {
    let weather: WeatherInfo
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    var config: [String: String]?

    private var visibilityCategory: String {
        guard let raw = weather.metrics?.visibility else { return "" }
        let digits = raw.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted).joined()
        let numeric = Double(digits) ?? 0
        let isKm = raw.lowercased().contains("km")
        let km = isKm ? numeric : numeric * 1.609
        switch km {
        case ..<1: return "Poor"
        case 1..<5: return "Moderate"
        case 5..<10: return "Good"
        default: return "Excellent"
        }
    }

    private var categoryColor: Color {
        switch visibilityCategory {
        case "Poor": return .red.opacity(0.85)
        case "Moderate": return .orange.opacity(0.9)
        case "Good": return DesignSystem.skyBlue
        default: return .green.opacity(0.85)
        }
    }

    private var style: String {
        config?["style"] ?? "standard"
    }

    var body: some View {
        let theme = viewModel.currentTheme(colorScheme: colorScheme)
        let textColor = theme.textColor
        let isCompact = style == "compact"

        VStack(alignment: .leading, spacing: 10) {
            Label("Visibility", systemImage: "eye.fill")
                .font(.caption.weight(.bold))
                .foregroundColor(textColor.opacity(0.6))

            if let vis = weather.metrics?.visibility {
                if isCompact {
                    HStack(spacing: 10) {
                        Text(vis)
                            .font(.system(size: 30, weight: .bold, design: viewModel.typography.design))
                            .foregroundColor(textColor)
                        Spacer(minLength: 0)
                        if !visibilityCategory.isEmpty {
                            Text(visibilityCategory)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(categoryColor.opacity(0.2)))
                                .overlay(Capsule().stroke(categoryColor, lineWidth: 0.5))
                                .foregroundColor(categoryColor)
                        }
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(vis)
                            .font(.system(size: 38, weight: .bold, design: viewModel.typography.design))
                            .foregroundColor(textColor)
                        if !visibilityCategory.isEmpty {
                            Text(visibilityCategory)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(categoryColor.opacity(0.2)))
                                .overlay(Capsule().stroke(categoryColor, lineWidth: 0.5))
                                .foregroundColor(categoryColor)
                        }
                    }

                    if !visibilityCategory.isEmpty {
                        Text("Current conditions suggest \(visibilityCategory.lowercased()) visibility.")
                            .font(.caption)
                            .foregroundColor(textColor.opacity(0.68))
                    }
                }
            } else {
                Text("Visibility data unavailable.")
                    .font(.caption)
                    .foregroundColor(textColor.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softGlassCard()
    }
}

// MARK: - Cloud Cover Widget

struct CloudCoverWidget: View {
    let weather: WeatherInfo
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    var config: [String: String]?

    private var parsedPercent: Int? {
        guard let raw = weather.metrics?.cloudCover else { return nil }
        return Int(raw.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
    }

    private var skyCondition: String {
        guard let pct = parsedPercent else { return "" }
        switch pct {
        case 0...20: return "Clear"
        case 21...40: return "Mostly Clear"
        case 41...70: return "Partly Cloudy"
        case 71...90: return "Mostly Cloudy"
        default: return "Overcast"
        }
    }

    private var style: String {
        config?["style"] ?? "standard"
    }

    var body: some View {
        let theme = viewModel.currentTheme(colorScheme: colorScheme)
        let textColor = theme.textColor
        let isCompact = style == "compact"

        VStack(alignment: .leading, spacing: 10) {
            Label("Cloud Cover", systemImage: "cloud.fill")
                .font(.caption.weight(.bold))
                .foregroundColor(textColor.opacity(0.6))

            if let pct = parsedPercent {
                if isCompact {
                    HStack(spacing: 10) {
                        Text("\(pct)%")
                            .font(.system(size: 30, weight: .bold, design: viewModel.typography.design))
                            .foregroundColor(textColor)
                        Spacer(minLength: 0)
                        Text(skyCondition)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(textColor.opacity(0.12)))
                            .overlay(Capsule().stroke(textColor.opacity(0.22), lineWidth: 0.5))
                            .foregroundColor(textColor.opacity(0.85))
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(pct)%")
                            .font(.system(size: 38, weight: .bold, design: viewModel.typography.design))
                            .foregroundColor(textColor)
                        Text(skyCondition)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(textColor.opacity(0.12)))
                            .overlay(Capsule().stroke(textColor.opacity(0.22), lineWidth: 0.5))
                            .foregroundColor(textColor.opacity(0.85))
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(textColor.opacity(0.08))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.5), Color.white.opacity(0.18)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * CGFloat(Double(pct) / 100.0))
                        }
                    }
                    .frame(height: 10)
                }
            } else {
                Text("Cloud cover data unavailable.")
                    .font(.caption)
                    .foregroundColor(textColor.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softGlassCard()
    }
}

// MARK: - Wind History Widget

struct WindHistoryWidget: View {
    private struct WindPoint: Identifiable {
        let id = UUID()
        let index: Int
        let time: String
        let sustained: Double
        let gust: Double?
    }

    let weather: WeatherInfo
    @ObservedObject var viewModel: WeatherViewModel
    let rangeHours: Int
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedIndex: Int? = nil
    var isChartInteracting: Binding<Bool>? = nil

    private func numericSpeed(_ s: String?) -> Double? {
        guard let s else { return nil }
        let cleaned = s.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        return Double(cleaned)
    }

    private var windPoints: [WindPoint] {
        Array((weather.allHourlyData ?? weather.hourlyForecast).prefix(rangeHours).enumerated()).compactMap { index, hour in
            guard let speed = numericSpeed(hour.windSpeed) else { return nil }
            return WindPoint(index: index, time: hour.time, sustained: speed, gust: hour.windGust)
        }
    }

    private var selected: WindPoint? {
        guard let selectedIndex, windPoints.indices.contains(selectedIndex) else { return nil }
        return windPoints[selectedIndex]
    }

    private var peakSpeed: Double { windPoints.map(\.sustained).max() ?? 0 }
    private var peakGust: Double { windPoints.compactMap(\.gust).max() ?? 0 }

    var body: some View {
        let theme = viewModel.currentTheme(colorScheme: colorScheme)
        let textColor = theme.textColor

        VStack(alignment: .leading, spacing: 12) {
            Label("Wind History", systemImage: "lines.measurement.horizontal")
                .font(.caption.weight(.bold))
                .foregroundColor(textColor.opacity(0.6))

            if windPoints.isEmpty {
                Text("Wind data unavailable.")
                    .font(.caption)
                    .foregroundColor(textColor.opacity(0.6))
            } else {
                Chart {
                    ForEach(windPoints) { point in
                        LineMark(
                            x: .value("Hour", point.index),
                            y: .value("Sustained", point.sustained),
                            series: .value("Type", "Sustained")
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(DesignSystem.skyBlue)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))

                        if let gust = point.gust {
                            LineMark(
                                x: .value("Hour", point.index),
                                y: .value("Gusts", gust),
                                series: .value("Type", "Gusts")
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(Color.orange.opacity(0.85))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                        }
                    }

                    if let sel = selected {
                        RuleMark(x: .value("Selected", sel.index))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
                            .foregroundStyle(textColor.opacity(0.35))
                            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(sel.time)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(textColor)
                                    Text(viewModel.formattedWindSpeedValue(sel.sustained))
                                        .font(.headline)
                                        .foregroundColor(textColor)
                                    if let gust = sel.gust {
                                        Text("Gust: \(viewModel.formattedWindSpeedValue(gust))")
                                            .font(.caption2)
                                            .foregroundColor(.orange.opacity(0.85))
                                    }
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(textColor.opacity(0.12), lineWidth: 0.5))
                            }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: 6)) { value in
                        AxisValueLabel {
                            if let idx = value.as(Int.self), windPoints.indices.contains(idx) {
                                Text(windPoints[idx].time)
                                    .font(.system(size: 10))
                                    .foregroundColor(textColor.opacity(0.6))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                            .foregroundStyle(textColor.opacity(0.15))
                        AxisValueLabel {
                            if let speed = value.as(Double.self) {
                                Text(viewModel.formattedWindSpeedValue(speed))
                                    .font(.system(size: 10))
                                    .foregroundColor(textColor.opacity(0.6))
                            }
                        }
                    }
                }
                .chartYScale(domain: 0...(max(peakGust, peakSpeed) * 1.2 + 2))
                .frame(height: 160)
                .padding(.top, 4)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        isChartInteracting?.wrappedValue = true
                                        guard let plotFrame = proxy.plotFrame else { return }
                                        let origin = geometry[plotFrame].origin
                                        if let idx: Int = proxy.value(atX: value.location.x - origin.x),
                                           let snap = windPoints.firstIndex(where: { $0.index == idx }) {
                                            if snap != selectedIndex {
                                                HapticsManager.shared.impact(style: .light)
                                            }
                                            selectedIndex = snap
                                        }
                                    }
                                    .onEnded { _ in
                                        isChartInteracting?.wrappedValue = false
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                            selectedIndex = nil
                                        }
                                    }
                            )
                    }
                }


                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Circle().fill(DesignSystem.skyBlue).frame(width: 8, height: 8)
                        Text("Sustained")
                            .font(.caption2)
                            .foregroundColor(textColor.opacity(0.7))
                    }
                    if windPoints.contains(where: { $0.gust != nil }) {
                        HStack(spacing: 6) {
                            Circle().fill(Color.orange.opacity(0.85)).frame(width: 8, height: 8)
                            Text("Gusts")
                                .font(.caption2)
                                .foregroundColor(textColor.opacity(0.7))
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softGlassCard()
    }
}
struct WeatherStatBlock: View {
    let title: String
    let value: String
    let textColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(textColor.opacity(0.62))
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(textColor)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusS)
                .fill(Color.white.opacity(0.08))
        )
    }
}

struct TooltipMetricChip: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .opacity(0.7)
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
        )
        .foregroundColor(.white.opacity(0.9))
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: min(maxWidth, proposal.width ?? currentX), height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
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
    let editSessionID: UUID
    let isEditMode: Bool
    let onRemove: () -> Void
    var onConfigure: (() -> Void)? = nil
    let content: () -> Content
    @AppStorage("Breezy.glassOpacity") private var glassOpacity: Double = 0.35
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            content()
                .allowsHitTesting(!isEditMode)
                .jiggle(enabled: isEditMode)
                .scaleEffect(isEditMode ? 0.98 : 1.0)
                .id("\(sectionId.uuidString)-\(editSessionID.uuidString)")
            
            if isEditMode {
                HStack(spacing: 0) {
                    if let onConfigure = onConfigure {
                        Button(action: onConfigure) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white.opacity(0.65))
                                .frame(width: 44, height: 36)
                        }
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 0.5, height: 22)
                    }

                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.red.opacity(0.6))
                            .frame(width: 44, height: 36)
                    }
                }
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial.opacity(glassOpacity))
                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                )
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
                .padding(.trailing, 22)
                .padding(.top, -10)
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
        HapticsManager.shared.impact(style: .medium)
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
            HapticsManager.shared.impact(style: .light)
            withAnimation(.snappy) {
                list.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

// MARK: - Smart Stack Widget

private let smartStackDefaultTypes: [WidgetType] = [
    .hourlyForecast,
    .deepDetails,
    .forecastNarrative,
    .rainSummary
]

private let smartStackSupportedTypes: [WidgetType] = [
    .hourlyForecast,
    .dailyForecast,
    .forecastNarrative,
    .deepDetails,
    .rainSummary,
    .rainfallToday,
    .windSummary,
    .uvIndex,
    .feelsLike,
    .humidityStrip,
    .visibilityCard,
    .cloudCoverCard
]

struct SmartStackWidget: View {
    @ObservedObject var viewModel: WeatherViewModel
    let weather: WeatherInfo
    let widget: DashboardWidget
    @Environment(\.colorScheme) var colorScheme
    
    private var stackedTypes: [WidgetType] {
        let configuredTypes = widget.config?["widgets"]?
            .split(separator: ",")
            .compactMap { WidgetType(rawValue: String($0)) }
            .filter { $0 != .smartStack && $0 != .radar }

        if let configuredTypes, !configuredTypes.isEmpty {
            return configuredTypes
        }

        return smartStackDefaultTypes
    }
    
    private var theme: WeatherTheme {
        viewModel.currentTheme(colorScheme: colorScheme)
    }

    private var featuredType: WidgetType {
        if stackedTypes.contains(.rainSummary), hasImmediateRainSignal {
            return .rainSummary
        }

        if stackedTypes.contains(.windSummary), hasStrongWindSignal {
            return .windSummary
        }

        if stackedTypes.contains(.uvIndex), hasHighUVSignal {
            return .uvIndex
        }

        if stackedTypes.contains(.hourlyForecast), !upcomingHours.isEmpty {
            return .hourlyForecast
        }

        if stackedTypes.contains(.forecastNarrative), viewModel.forecastNarrativeSummary != nil {
            return .forecastNarrative
        }

        if stackedTypes.contains(.deepDetails) {
            return .deepDetails
        }

        return stackedTypes.first ?? .deepDetails
    }

    private var featuredReason: String {
        switch featuredType {
        case .rainSummary:
            return "Showing the biggest rain signal in your next few hours."
        case .windSummary:
            return "Wind is the strongest weather story right now."
        case .uvIndex:
            return "UV exposure is elevated, so this is the most useful card right now."
        case .hourlyForecast:
            return "Showing the literal next few hours so you can glance ahead quickly."
        case .forecastNarrative:
            return "There isn't a stronger live signal, so the stack is surfacing the forecast story."
        case .deepDetails:
            return "Conditions are steady, so the stack is surfacing your core metrics."
        default:
            return "This card is the most relevant weather detail right now."
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Smart Stack", systemImage: "square.3.layers.3d")
                        .font(.caption.weight(.bold))
                        .foregroundColor(theme.textColor.opacity(0.62))

                    Text(featuredType.rawValue)
                        .font(.headline)
                        .foregroundColor(theme.textColor)
                }

                Text(featuredReason)
                    .font(.caption)
                    .foregroundColor(theme.textColor.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }

            stackedWidgetView(for: featuredType)
                .frame(minHeight: 232)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softGlassCard()
    }
    
    @ViewBuilder
    private func stackedWidgetView(for type: WidgetType) -> some View {
        switch type {
        case .hourlyForecast:
            SmartStackPageCard(
                title: "Next Few Hours",
                subtitle: "Quick temperature outlook",
                icon: "clock",
                accent: .orange,
                textColor: theme.textColor
            ) {
                HStack(spacing: 10) {
                    ForEach(Array(upcomingHours.enumerated()), id: \.offset) { entry in
                        let hour = entry.element
                        VStack(spacing: 8) {
                            Text(displayTime(for: hour))
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(theme.textColor.opacity(0.62))

                            if viewModel.useMinimalistIcons {
                                Image(systemName: WeatherIconHelper.minimalistIcon(for: hour.condition ?? weather.condition))
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(theme.textColor)
                            } else {
                                Text(hour.emoji ?? weather.emoji)
                                    .font(.system(size: 18))
                            }

                            Text(formatTemperature(hour.temperatureRaw))
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(theme.textColor)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        case .dailyForecast:
            SmartStackPageCard(
                title: "Daily Snapshot",
                subtitle: "Top forecast for the next days",
                icon: "calendar",
                accent: .blue,
                textColor: theme.textColor
            ) {
                VStack(spacing: 12) {
                    ForEach(weather.dailyForecast.prefix(3)) { day in
                        HStack(spacing: 12) {
                            Text(day.dayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(theme.textColor)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if viewModel.useMinimalistIcons {
                                Image(systemName: WeatherIconHelper.minimalistIcon(for: day.condition))
                                    .foregroundColor(theme.textColor.opacity(0.88))
                            } else {
                                Text(day.emoji)
                            }

                            Text(day.lowTemp)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(theme.textColor.opacity(0.55))

                            Text(day.highTemp)
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(theme.textColor)
                        }
                    }
                }
            }
        case .forecastNarrative:
            SmartStackPageCard(
                title: "Forecast Story",
                subtitle: "What matters most next",
                icon: "text.justify.left",
                accent: .purple,
                textColor: theme.textColor
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.forecastNarrativeSummary?.headline ?? "Mostly steady weather through the next few days.")
                        .font(.headline)
                        .foregroundColor(theme.textColor)
                        .fixedSize(horizontal: false, vertical: true)

                    if let detail = viewModel.forecastNarrativeSummary?.detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundColor(theme.textColor.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                            .lineLimit(4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .deepDetails:
            SmartStackPageCard(
                title: "Deep Details",
                subtitle: "A tighter view of the essentials",
                icon: "speedometer",
                accent: .teal,
                textColor: theme.textColor
            ) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    SmartStackMetricTile(title: "Humidity", value: humidityText, textColor: theme.textColor)
                    SmartStackMetricTile(title: "Feels Like", value: weather.feelsLike ?? weather.temperature, textColor: theme.textColor)
                    SmartStackMetricTile(title: "Wind", value: weather.metrics?.windSpeed ?? "Calm", textColor: theme.textColor)
                    SmartStackMetricTile(title: "Rain", value: weather.metrics?.rainChance ?? weather.dailyForecast.first?.chanceOfRain ?? "0%", textColor: theme.textColor)
                }
            }
        case .rainSummary:
            SmartStackPageCard(
                title: "Rain Summary",
                subtitle: "Precipitation outlook",
                icon: "cloud.rain.fill",
                accent: .blue,
                textColor: theme.textColor
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(weather.metrics?.rainChance ?? weather.dailyForecast.first?.chanceOfRain ?? "0%")
                            .font(.system(size: 34, weight: .bold, design: viewModel.typography.design))
                            .foregroundColor(theme.textColor)

                        Text("chance")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(theme.textColor.opacity(0.62))
                    }

                    Text(rainSummaryText)
                        .font(.subheadline)
                        .foregroundColor(theme.textColor.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .rainfallToday:
            SmartStackPageCard(
                title: "Rainfall Today",
                subtitle: "Current accumulation",
                icon: "drop.fill",
                accent: .blue,
                textColor: theme.textColor
            ) {
                HStack {
                    SmartStackMetricTile(title: "Total", value: weather.metrics?.todayRainfall ?? "0 mm", textColor: theme.textColor)
                    SmartStackMetricTile(title: "Peak Intensity", value: weather.metrics?.todayMaxRainIntensity ?? "0 mm/h", textColor: theme.textColor)
                }
            }
        case .windSummary:
            SmartStackPageCard(
                title: "Wind Summary",
                subtitle: "Speed and direction",
                icon: "wind",
                accent: .cyan,
                textColor: theme.textColor
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(weather.metrics?.windSpeed ?? "Calm")
                            .font(.system(size: 32, weight: .bold, design: viewModel.typography.design))
                            .foregroundColor(theme.textColor)

                        Text(weather.metrics?.windDirectionCardinal ?? "")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(theme.textColor.opacity(0.6))
                    }

                    HStack {
                        SmartStackMetricTile(title: "Gust", value: weather.metrics?.windGust ?? "None", textColor: theme.textColor)
                        SmartStackMetricTile(title: "Direction", value: weather.metrics?.windDirectionCardinal ?? "Variable", textColor: theme.textColor)
                    }
                }
            }
        case .uvIndex:
            SmartStackPageCard(
                title: "UV Index",
                subtitle: "Exposure right now",
                icon: "sun.max.fill",
                accent: .yellow,
                textColor: theme.textColor
            ) {
                HStack(alignment: .center, spacing: 16) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 8)
                            .frame(width: 78, height: 78)

                        Circle()
                            .trim(from: 0, to: min(CGFloat((weather.metrics?.uvIndex ?? 0)) / 11, 1))
                            .stroke(Color.yellow, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 78, height: 78)

                        Text("\(weather.metrics?.uvIndex ?? 0)")
                            .font(.title2.bold())
                            .foregroundColor(theme.textColor)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(weather.metrics?.uvIndexCategory ?? "Low")
                            .font(.headline)
                            .foregroundColor(theme.textColor)

                        Text("Use sunscreen if you are outside for long stretches.")
                            .font(.subheadline)
                            .foregroundColor(theme.textColor.opacity(0.68))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .feelsLike:
            SmartStackPageCard(
                title: "Feels Like",
                subtitle: "How it actually feels outside",
                icon: "thermometer.medium",
                accent: .orange,
                textColor: theme.textColor
            ) {
                HStack {
                    Text(weather.feelsLike ?? weather.temperature)
                        .font(.system(size: 44, weight: .bold, design: viewModel.typography.design))
                        .foregroundColor(theme.textColor)
                    Spacer()
                }
            }
        case .humidityStrip:
            SmartStackPageCard(
                title: "Humidity",
                subtitle: "Moisture in the air",
                icon: "humidity.fill",
                accent: .mint,
                textColor: theme.textColor
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(humidityText)
                        .font(.system(size: 38, weight: .bold, design: viewModel.typography.design))
                        .foregroundColor(theme.textColor)

                    Text("Cloud cover \(weather.metrics?.cloudCover ?? "0%")")
                        .font(.subheadline)
                        .foregroundColor(theme.textColor.opacity(0.68))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .visibilityCard:
            SmartStackPageCard(
                title: "Visibility",
                subtitle: "How far you can see",
                icon: "eye.fill",
                accent: .indigo,
                textColor: theme.textColor
            ) {
                HStack {
                    Text(weather.metrics?.visibility ?? "Clear")
                        .font(.system(size: 34, weight: .bold, design: viewModel.typography.design))
                        .foregroundColor(theme.textColor)
                    Spacer()
                }
            }
        case .cloudCoverCard:
            SmartStackPageCard(
                title: "Cloud Cover",
                subtitle: "Sky coverage right now",
                icon: "cloud.fill",
                accent: .gray,
                textColor: theme.textColor
            ) {
                HStack {
                    Text(weather.metrics?.cloudCover ?? "0%")
                        .font(.system(size: 34, weight: .bold, design: viewModel.typography.design))
                        .foregroundColor(theme.textColor)
                    Spacer()
                }
            }
        default:
            SmartStackPageCard(
                title: "Coming Soon",
                subtitle: "This widget type is not supported in Smart Stack yet.",
                icon: "wand.and.rays",
                accent: .pink,
                textColor: theme.textColor
            ) {
                Text("Choose another card from the stack settings for a smoother preview.")
                    .font(.subheadline)
                    .foregroundColor(theme.textColor.opacity(0.7))
            }
        }
    }
    
    private var humidityText: String {
        if let humidity = weather.metrics?.humidity {
            return "\(humidity)%"
        }
        return weather.dailyForecast.first?.humidity ?? "0%"
    }

    private var rainSummaryText: String {
        let nextRainDay = weather.dailyForecast.first(where: {
            guard let chance = $0.chanceOfRain?.replacingOccurrences(of: "%", with: ""),
                  let rainChance = Int(chance) else { return false }
            return rainChance >= 40
        })

        if let nextRainDay {
            return "The next stronger rain signal shows up on \(nextRainDay.dayName) with \(nextRainDay.chanceOfRain ?? "0%") odds."
        }

        return "The next few days look mostly dry, with only light precipitation risk in the outlook."
    }

    private func formatTemperature(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        let suffix = weather.temperature.contains("F") ? "°F" : "°C"
        return "\(rounded)\(suffix)"
    }

    private var upcomingHours: [HourlyForecast] {
        let source = (weather.allHourlyData ?? weather.hourlyForecast)
            .sorted { lhs, rhs in
                switch (lhs.sourceDate, rhs.sourceDate) {
                case let (left?, right?):
                    return left < right
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                case (nil, nil):
                    return lhs.hourValue < rhs.hourValue
                }
            }
        let now = Date()
        let filtered = source.filter { hour in
            guard let sourceDate = hour.sourceDate else { return true }
            return sourceDate >= now.addingTimeInterval(-1800)
        }

        let upcoming = Array(filtered.prefix(4))
        if !upcoming.isEmpty {
            return upcoming
        }
        return Array(weather.hourlyForecast.prefix(4))
    }

    private func displayTime(for hour: HourlyForecast) -> String {
        if let sourceDate = hour.sourceDate {
            return sourceDate.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)))
        }

        let trimmed = hour.time.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 1 {
            return trimmed
        }

        let normalizedHour = hour.hourValue % 24
        guard let fallbackDate = Calendar.current.date(bySettingHour: normalizedHour, minute: 0, second: 0, of: Date()) else {
            return "\(normalizedHour):00"
        }

        return fallbackDate.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)))
    }

    private var hasImmediateRainSignal: Bool {
        if let minuteForecast = weather.metrics?.minuteForecast,
           minuteForecast.contains(where: { $0.precipitationChance >= 0.35 || $0.precipitationIntensity > 0 }) {
            return true
        }

        if let rainChance = weather.metrics?.rainChance?.replacingOccurrences(of: "%", with: ""),
           let value = Int(rainChance),
           value >= 55 {
            return true
        }

        if let chanceOfRain = weather.dailyForecast.first?.chanceOfRain?.replacingOccurrences(of: "%", with: ""),
           let value = Int(chanceOfRain),
           value >= 55 {
            return true
        }

        return false
    }

    private var hasHighUVSignal: Bool {
        (weather.metrics?.uvIndex ?? 0) >= 7
    }

    private var hasStrongWindSignal: Bool {
        guard let windValue = parsedWindSpeedValue(from: weather.metrics?.windSpeed) else { return false }
        return windValue >= 28
    }

    private func parsedWindSpeedValue(from speed: String?) -> Double? {
        guard let speed else { return nil }
        let cleaned = speed
            .replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        return Double(cleaned)
    }
}

private struct SmartStackPageCard<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color
    let textColor: Color
    let content: () -> Content

    init(
        title: String,
        subtitle: String,
        icon: String,
        accent: Color,
        textColor: Color,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accent = accent
        self.textColor = textColor
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(accent.opacity(0.16))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(textColor)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(textColor.opacity(0.6))
                }
            }

            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                )
        )
    }
}

private struct SmartStackMetricTile: View {
    let title: String
    let value: String
    let textColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundColor(textColor.opacity(0.5))

            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundColor(textColor)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                .fill(Color.white.opacity(0.05))
        )
    }
}

// MARK: - Gallery & Config

struct WidgetGalleryView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    let onAdd: (WidgetType) -> Void
    
    private let columns = [
        GridItem(.flexible(), spacing: DesignSystem.spacingS),
        GridItem(.flexible(), spacing: DesignSystem.spacingS)
    ]
    
    var body: some View {
        ZStack {
            let theme = viewModel.currentTheme(colorScheme: colorScheme)
            AnimatedGradientBackground(colors: [theme.topColor, theme.bottomColor])
            
            VStack(spacing: 0) {
                // Custom Header
                HStack {
                    Spacer()
                    Text("Widget Gallery")
                        .font(.system(size: 17, weight: .semibold, design: viewModel.typography.design))
                        .foregroundColor(theme.textColor)
                    Spacer()
                }
                .overlay(alignment: .trailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(theme.textColor.opacity(0.8))
                            .font(.title2)
                    }
                    .padding(.trailing, DesignSystem.spacingM)
                }
                .padding(.top, 12)
                .padding(.bottom, 8)
                
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.spacingL) {
                        // Title Section
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Customise Dashboard")
                                .font(.system(size: 28, weight: .bold, design: viewModel.typography.design))
                                .foregroundColor(theme.textColor)
                            
                            Text("Tap a widget to add it to your main view.")
                                .font(.system(size: 16, weight: .medium, design: viewModel.typography.design))
                                .foregroundColor(theme.textColor.opacity(0.7))
                        }
                        .padding(.horizontal)
                        .padding(.top, DesignSystem.spacingS)
                        
                        // Categorized Grid
                        ForEach(WidgetCategory.allCases) { category in
                            VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
                                Text(category.rawValue.uppercased())
                                    .font(.system(size: 13, weight: .bold, design: viewModel.typography.design))
                                    .tracking(1.2)
                                    .foregroundColor(theme.textColor.opacity(0.6))
                                    .padding(.horizontal)
                                
                                LazyVGrid(columns: columns, spacing: DesignSystem.spacingS) {
                                    ForEach(WidgetType.allCases.filter { $0.category == category }) { type in
                                        Button {
                                            onAdd(type)
                                        } label: {
                                            VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
                                                ZStack {
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .fill(DesignSystem.skyBlue.opacity(0.15))
                                                        .frame(width: 44, height: 44)
                                                    Image(systemName: type.icon)
                                                        .font(.system(size: 22, weight: .medium))
                                                        .foregroundColor(DesignSystem.skyBlue)
                                                }
                                                
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(type.rawValue)
                                                        .font(.system(size: 16, weight: .bold, design: viewModel.typography.design))
                                                        .foregroundColor(theme.textColor)
                                                        .multilineTextAlignment(.leading)
                                                    
                                                    Text(description(for: type))
                                                        .font(.system(size: 12, weight: .medium, design: viewModel.typography.design))
                                                        .foregroundColor(theme.textColor.opacity(0.5))
                                                        .multilineTextAlignment(.leading)
                                                        .lineLimit(2)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                }
                                            }
                                            .padding(DesignSystem.spacingM)
                                            .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                                            .background(
                                                RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                                                    .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                                                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                                            )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }
    
    private func description(for type: WidgetType) -> String {
        switch type {
        case .hourlyForecast: return "Hourly strip, adjustable range"
        case .dailyForecast: return "10-day forecast"
        case .forecastNarrative: return "Forecast narrative"
        case .deepDetails: return "Metrics grid"
        case .rainSummary: return "Rain outlook"
        case .rainfallToday: return "Today's rainfall"
        case .minutePrecipitation: return "Next-hour rain graph"
        case .windSummary: return "Wind speed & direction"
        case .windGraph: return "Wind speed chart"
        case .radar: return "Live radar"
        case .uvIndex: return "UV index"
        case .feelsLike: return "Feels like temperature"
        case .sunPath: return "Sun arc & countdown"
        case .moonPhase: return "Moon phase"
        case .uvIndexCurve: return "UV curve chart"
        case .hourlyTemperatures: return "Daily hourly temperature chart"
        case .humidityStrip: return "Hourly humidity chart"
        case .precipitationTimeline: return "7-day rain probability bars"
        case .visibilityCard: return "Current visibility & category"
        case .cloudCoverCard: return "Cloud cover percentage"
        case .windHistory: return "Sustained vs gust wind chart"
        case .smartStack: return "Adaptive widget stack"
        }
    }
}

struct WidgetConfigView: View {
    @State var widget: DashboardWidget
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    let onSave: (DashboardWidget) -> Void

    private var configDescription: String {
        switch widget.type {
        case .hourlyForecast:
            return "Choose how many hours this forecast card shows and how dense the layout should feel."
        case .deepDetails:
            return "Select which metrics to display in this Deep Details card."
        case .windSummary:
            return "Choose how wind should be presented on your dashboard."
        case .forecastNarrative:
            return "Pick whether the forecast story stays compact or includes extra context."
        case .minutePrecipitation:
            return "Choose how much short-range rain detail this card should show."
        case .windGraph:
            return "Pick how far ahead the wind chart should look."
        case .humidityStrip:
            return "Choose how many hours of humidity data to display."
        case .windHistory:
            return "Pick how far ahead to show sustained vs gust wind speeds."
        case .uvIndex:
            return "Control how prominent the UV reading is and whether the category label stays visible."
        case .sunPath:
            return "Switch between the full sun arc and a quieter compact layout, with optional live countdown."
        case .moonPhase:
            return "Adjust the moon card density and the size of the moon visualization."
        case .dailyForecast:
            return "Control how many days appear in the forecast and whether to show condition icons."
        case .hourlyTemperatures:
            return "Adjust the temperature chart range and visual style."
        case .rainSummary:
            return "Configure what rain information is displayed and how detailed it is."
        case .rainfallToday:
            return "Choose rainfall display units and detail level."
        case .precipitationTimeline:
            return "Set how many hours of precipitation chance to display."
        case .feelsLike:
            return "Choose how the feels-like temperature is presented."
        case .uvIndexCurve:
            return "Adjust the UV forecast curve range and display options."
        case .visibilityCard:
            return "Configure visibility display style and units."
        case .cloudCoverCard:
            return "Choose how cloud cover data is visualized."
        case .radar:
            return "Set the default radar map layer and zoom level."
        case .smartStack:
            return "Choose which cards the smart stack can surface when their weather signal matters most."
        default:
            return "Adjust this widget."
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                let theme = viewModel.currentTheme(colorScheme: colorScheme)
                AnimatedGradientBackground(colors: [theme.topColor, theme.bottomColor])
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(configDescription)
                            .font(.subheadline)
                            .foregroundColor(theme.textColor.opacity(0.7))
                            .padding(.horizontal)

                        if widget.type == .hourlyForecast {
                            VStack(alignment: .leading, spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Forecast Range")
                                        .font(.subheadline)
                                        .foregroundColor(theme.textColor.opacity(0.7))
                                        .padding(.horizontal)

                                    Picker("Forecast Range", selection: Binding(
                                        get: { widget.config?["rangeHours"] ?? "24" },
                                        set: { newValue in
                                            if widget.config == nil { widget.config = [:] }
                                            widget.config?["rangeHours"] = newValue
                                        }
                                    )) {
                                        Text("12 hr").tag("12")
                                        Text("24 hr").tag("24")
                                    }
                                    .pickerStyle(.segmented)
                                    .padding(.horizontal)
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Layout Density")
                                        .font(.subheadline)
                                        .foregroundColor(theme.textColor.opacity(0.7))
                                        .padding(.horizontal)

                                    Picker("Layout Density", selection: Binding(
                                        get: { widget.config?["density"] ?? "regular" },
                                        set: { newValue in
                                            if widget.config == nil { widget.config = [:] }
                                            widget.config?["density"] = newValue
                                        }
                                    )) {
                                        Text("Compact").tag("compact")
                                        Text("Regular").tag("regular")
                                    }
                                    .pickerStyle(.segmented)
                                    .padding(.horizontal)
                                }
                            }
                        }

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

                        if widget.type == .forecastNarrative {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Story Density")
                                    .font(.subheadline)
                                    .foregroundColor(theme.textColor.opacity(0.7))
                                    .padding(.horizontal)

                                Picker("Story Density", selection: Binding(
                                    get: { widget.config?["style"] ?? "expanded" },
                                    set: { newValue in
                                        if widget.config == nil { widget.config = [:] }
                                        widget.config?["style"] = newValue
                                    }
                                )) {
                                    Text("Compact").tag("compact")
                                    Text("Expanded").tag("expanded")
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal)
                            }
                        }

                        if widget.type == .deepDetails {
                            let selectedMetrics = widget.visibleMetrics ?? Array(viewModel.visibleMetrics)

                            VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
                                Text("Pick metrics")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(theme.textColor.opacity(0.65))
                                    .padding(.top, 4)

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignSystem.spacingS) {
                                    ForEach(WeatherMetric.allCases) { metric in
                                        let isSelected = selectedMetrics.contains(metric)
                                        let canDeselect = selectedMetrics.count > 1

                                        Button {
                                            if widget.visibleMetrics == nil {
                                                widget.visibleMetrics = selectedMetrics
                                            }
                                            if isSelected {
                                                if canDeselect {
                                                    widget.visibleMetrics?.removeAll(where: { $0 == metric })
                                                }
                                            } else {
                                                widget.visibleMetrics?.append(metric)
                                            }
                                        } label: {
                                            HStack(spacing: 8) {
                                                Image(systemName: metric.icon)
                                                    .font(.caption)
                                                    .foregroundColor(theme.textColor.opacity(0.75))
                                                Text(metric.rawValue)
                                                    .font(.caption)
                                                    .foregroundColor(theme.textColor)
                                                    .lineLimit(1)
                                                Spacer(minLength: 4)
                                                if isSelected {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundColor(canDeselect ? DesignSystem.skyBlue : theme.textColor.opacity(0.35))
                                                        .font(.caption)
                                                }
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: DesignSystem.radiusS)
                                                    .fill(isSelected ? DesignSystem.skyBlue.opacity(0.16) : Color.white.opacity(0.07))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: DesignSystem.radiusS)
                                                            .stroke(isSelected ? DesignSystem.skyBlue.opacity(0.45) : Color.white.opacity(0.12), lineWidth: 0.8)
                                                    )
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                if !selectedMetrics.isEmpty {
                                    Text("Selected (drag to reorder)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(theme.textColor.opacity(0.65))

                                    List {
                                        ForEach(selectedMetrics) { metric in
                                            HStack(spacing: 8) {
                                                Image(systemName: metric.icon)
                                                    .font(.caption)
                                                    .foregroundColor(theme.textColor.opacity(0.75))
                                                Text(metric.rawValue)
                                                    .font(.caption)
                                                    .foregroundColor(theme.textColor)
                                                    .lineLimit(1)
                                                Spacer(minLength: 4)
                                                Button {
                                                    if widget.visibleMetrics == nil {
                                                        widget.visibleMetrics = selectedMetrics
                                                    }
                                                    if (widget.visibleMetrics?.count ?? 0) > 1 {
                                                        widget.visibleMetrics?.removeAll(where: { $0 == metric })
                                                    }
                                                } label: {
                                                    Image(systemName: "minus.circle.fill")
                                                        .font(.caption)
                                                        .foregroundColor((selectedMetrics.count > 1) ? DesignSystem.skyBlue : theme.textColor.opacity(0.35))
                                                }
                                                .buttonStyle(.plain)
                                                .disabled(selectedMetrics.count <= 1)
                                            }
                                            .padding(.vertical, 10)
                                            .listRowBackground(Color.white.opacity(0.06))
                                        }
                                        .onMove { from, to in
                                            if widget.visibleMetrics == nil {
                                                widget.visibleMetrics = selectedMetrics
                                            }
                                            widget.visibleMetrics?.move(fromOffsets: from, toOffset: to)
                                        }
                                    }
                                    .environment(\.editMode, .constant(.active))
                                    .listStyle(.plain)
                                    .scrollContentBackground(.hidden)
                                    .frame(height: max(84, CGFloat(selectedMetrics.count) * 60))
                                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.radiusS))
                                }
                            }
                        }

                        if widget.type == .smartStack {
                            let selectedTypes = widget.config?["widgets"]?
                                .split(separator: ",")
                                .compactMap { WidgetType(rawValue: String($0)) }
                                .filter { smartStackSupportedTypes.contains($0) } ?? smartStackDefaultTypes

                            VStack(alignment: .leading, spacing: 14) {
                                Text("Stacked Cards")
                                    .font(.subheadline)
                                    .foregroundColor(theme.textColor.opacity(0.7))
                                    .padding(.horizontal)

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                    ForEach(smartStackSupportedTypes) { stackType in
                                        let isSelected = selectedTypes.contains(stackType)
                                        let canRemove = selectedTypes.count > 1

                                        Button {
                                            var updatedTypes = selectedTypes

                                            if isSelected {
                                                guard canRemove else { return }
                                                updatedTypes.removeAll { $0 == stackType }
                                            } else {
                                                updatedTypes.append(stackType)
                                            }

                                            if widget.config == nil { widget.config = [:] }
                                            widget.config?["widgets"] = updatedTypes.map(\.rawValue).joined(separator: ",")
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: stackType.icon)
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundColor(isSelected ? DesignSystem.skyBlue : theme.textColor.opacity(0.65))

                                                Text(stackType.rawValue)
                                                    .font(.caption.weight(.medium))
                                                    .foregroundColor(theme.textColor)
                                                    .multilineTextAlignment(.leading)

                                                Spacer(minLength: 4)

                                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                    .foregroundColor(isSelected ? DesignSystem.skyBlue : theme.textColor.opacity(0.35))
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 12)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(
                                                RoundedRectangle(cornerRadius: DesignSystem.radiusS)
                                                    .fill(isSelected ? DesignSystem.skyBlue.opacity(0.14) : Color.white.opacity(0.06))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: DesignSystem.radiusS)
                                                            .stroke(isSelected ? DesignSystem.skyBlue.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 0.8)
                                                    )
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)

                            }
                        }

                        if widget.type == .humidityStrip || widget.type == .windHistory {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Forecast Range")
                                    .font(.subheadline)
                                    .foregroundColor(theme.textColor.opacity(0.7))
                                    .padding(.horizontal)

                                Picker("Forecast Range", selection: Binding(
                                    get: { widget.config?["rangeHours"] ?? "24" },
                                    set: { newValue in
                                        if widget.config == nil { widget.config = [:] }
                                        widget.config?["rangeHours"] = newValue
                                    }
                                )) {
                                    Text("12 hr").tag("12")
                                    Text("24 hr").tag("24")
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal)
                            }
                        }

                        if widget.type == .uvIndex {
                            VStack(alignment: .leading, spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Visual Style")
                                        .font(.subheadline)
                                        .foregroundColor(theme.textColor.opacity(0.7))
                                        .padding(.horizontal)

                                    Picker("Visual Style", selection: Binding(
                                        get: { widget.config?["style"] ?? "standard" },
                                        set: { newValue in
                                            if widget.config == nil { widget.config = [:] }
                                            widget.config?["style"] = newValue
                                        }
                                    )) {
                                        Text("Minimal").tag("minimal")
                                        Text("Standard").tag("standard")
                                        Text("Emphasis").tag("emphasis")
                                    }
                                    .pickerStyle(.segmented)
                                    .padding(.horizontal)
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Category Label")
                                        .font(.subheadline)
                                        .foregroundColor(theme.textColor.opacity(0.7))
                                        .padding(.horizontal)

                                    Picker("Category Label", selection: Binding(
                                        get: { widget.config?["showCategory"] ?? "true" },
                                        set: { newValue in
                                            if widget.config == nil { widget.config = [:] }
                                            widget.config?["showCategory"] = newValue
                                        }
                                    )) {
                                        Text("Show").tag("true")
                                        Text("Hide").tag("false")
                                    }
                                    .pickerStyle(.segmented)
                                    .padding(.horizontal)
                                }
                            }
                        }

                        if widget.type == .sunPath {
                            VStack(alignment: .leading, spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Layout Style")
                                        .font(.subheadline)
                                        .foregroundColor(theme.textColor.opacity(0.7))
                                        .padding(.horizontal)

                                    Picker("Layout Style", selection: Binding(
                                        get: { widget.config?["style"] ?? "full" },
                                        set: { newValue in
                                            if widget.config == nil { widget.config = [:] }
                                            widget.config?["style"] = newValue
                                        }
                                    )) {
                                        Text("Full").tag("full")
                                        Text("Minimal").tag("minimal")
                                    }
                                    .pickerStyle(.segmented)
                                    .padding(.horizontal)
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Live Countdown")
                                        .font(.subheadline)
                                        .foregroundColor(theme.textColor.opacity(0.7))
                                        .padding(.horizontal)

                                    Picker("Live Countdown", selection: Binding(
                                        get: { widget.config?["showCountdown"] ?? "true" },
                                        set: { newValue in
                                            if widget.config == nil { widget.config = [:] }
                                            widget.config?["showCountdown"] = newValue
                                        }
                                    )) {
                                        Text("Show").tag("true")
                                        Text("Hide").tag("false")
                                    }
                                    .pickerStyle(.segmented)
                                    .padding(.horizontal)
                                }
                            }
                        }

                        if widget.type == .moonPhase {
                            VStack(alignment: .leading, spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Detail Level")
                                        .font(.subheadline)
                                        .foregroundColor(theme.textColor.opacity(0.7))
                                        .padding(.horizontal)

                                    Picker("Detail Level", selection: Binding(
                                        get: { widget.config?["style"] ?? "full" },
                                        set: { newValue in
                                            if widget.config == nil { widget.config = [:] }
                                            widget.config?["style"] = newValue
                                        }
                                    )) {
                                        Text("Compact").tag("compact")
                                        Text("Full").tag("full")
                                    }
                                    .pickerStyle(.segmented)
                                    .padding(.horizontal)
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Moon Size")
                                        .font(.subheadline)
                                        .foregroundColor(theme.textColor.opacity(0.7))
                                        .padding(.horizontal)

                                    Picker("Moon Size", selection: Binding(
                                        get: { widget.config?["size"] ?? "medium" },
                                        set: { newValue in
                                            if widget.config == nil { widget.config = [:] }
                                            widget.config?["size"] = newValue
                                        }
                                    )) {
                                        Text("Small").tag("small")
                                        Text("Medium").tag("medium")
                                        Text("Large").tag("large")
                                    }
                                    .pickerStyle(.segmented)
                                     .padding(.horizontal)
                                 }
                             }
                         }
                        
                        if widget.type == .rainSummary {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Detail Level")
                                    .font(.subheadline)
                                    .foregroundColor(theme.textColor.opacity(0.7))
                                    .padding(.horizontal)
                                Picker("Style", selection: Binding(
                                    get: { widget.config?["style"] ?? "standard" },
                                    set: { newValue in
                                        if widget.config == nil { widget.config = [:] }
                                        widget.config?["style"] = newValue
                                    }
                                )) {
                                    Text("Compact").tag("compact")
                                    Text("Standard").tag("standard")
                                    Text("Detailed").tag("detailed")
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal)
                            }
                        }
                        
                        if widget.type == .rainfallToday {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Display Style")
                                    .font(.subheadline)
                                    .foregroundColor(theme.textColor.opacity(0.7))
                                    .padding(.horizontal)
                                Picker("Style", selection: Binding(
                                    get: { widget.config?["style"] ?? "standard" },
                                    set: { newValue in
                                        if widget.config == nil { widget.config = [:] }
                                        widget.config?["style"] = newValue
                                    }
                                )) {
                                    Text("Minimal").tag("minimal")
                                    Text("Standard").tag("standard")
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal)
                            }
                        }
                        
                        if widget.type == .feelsLike {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Presentation")
                                    .font(.subheadline)
                                    .foregroundColor(theme.textColor.opacity(0.7))
                                    .padding(.horizontal)
                                Picker("Style", selection: Binding(
                                    get: { widget.config?["style"] ?? "standard" },
                                    set: { newValue in
                                        if widget.config == nil { widget.config = [:] }
                                        widget.config?["style"] = newValue
                                    }
                                )) {
                                    Text("Compact").tag("compact")
                                    Text("Standard").tag("standard")
                                    Text("Emphasis").tag("emphasis")
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal)
                            }
                        }
                        
                        if widget.type == .hourlyTemperatures {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Chart Range")
                                    .font(.subheadline)
                                    .foregroundColor(theme.textColor.opacity(0.7))
                                    .padding(.horizontal)
                                Picker("Range", selection: Binding(
                                    get: { widget.config?["rangeHours"] ?? "24" },
                                    set: { newValue in
                                        if widget.config == nil { widget.config = [:] }
                                        widget.config?["rangeHours"] = newValue
                                    }
                                )) {
                                    Text("All").tag("0")
                                    Text("12 hr").tag("12")
                                    Text("24 hr").tag("24")
                                    Text("48 hr").tag("48")
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal)
                            }
                        }
                        
                        if widget.type == .precipitationTimeline {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Forecast Days")
                                    .font(.subheadline)
                                    .foregroundColor(theme.textColor.opacity(0.7))
                                    .padding(.horizontal)
                                Picker("Days", selection: Binding(
                                    get: { widget.config?["rangeDays"] ?? "0" },
                                    set: { newValue in
                                        if widget.config == nil { widget.config = [:] }
                                        widget.config?["rangeDays"] = newValue
                                    }
                                )) {
                                    Text("All").tag("0")
                                    Text("5 days").tag("5")
                                    Text("7 days").tag("7")
                                    Text("10 days").tag("10")
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal)
                            }
                        }
                        
                        if widget.type == .uvIndexCurve {
                            VStack(alignment: .leading, spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Chart Range")
                                        .font(.subheadline)
                                        .foregroundColor(theme.textColor.opacity(0.7))
                                        .padding(.horizontal)
                                    Picker("Range", selection: Binding(
                                        get: { widget.config?["rangeHours"] ?? "24" },
                                        set: { newValue in
                                            if widget.config == nil { widget.config = [:] }
                                            widget.config?["rangeHours"] = newValue
                                        }
                                    )) {
                                        Text("12 hr").tag("12")
                                        Text("24 hr").tag("24")
                                    }
                                    .pickerStyle(.segmented)
                                    .padding(.horizontal)
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Peak Indicator")
                                        .font(.subheadline)
                                        .foregroundColor(theme.textColor.opacity(0.7))
                                        .padding(.horizontal)
                                    Picker("Peak", selection: Binding(
                                        get: { widget.config?["showPeak"] ?? "true" },
                                        set: { newValue in
                                            if widget.config == nil { widget.config = [:] }
                                            widget.config?["showPeak"] = newValue
                                        }
                                    )) {
                                        Text("Show").tag("true")
                                        Text("Hide").tag("false")
                                    }
                                    .pickerStyle(.segmented)
                                    .padding(.horizontal)
                                }
                            }
                        }
                        
                        if widget.type == .visibilityCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Display Style")
                                    .font(.subheadline)
                                    .foregroundColor(theme.textColor.opacity(0.7))
                                    .padding(.horizontal)
                                Picker("Style", selection: Binding(
                                    get: { widget.config?["style"] ?? "standard" },
                                    set: { newValue in
                                        if widget.config == nil { widget.config = [:] }
                                        widget.config?["style"] = newValue
                                    }
                                )) {
                                    Text("Compact").tag("compact")
                                    Text("Standard").tag("standard")
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal)
                            }
                        }
                        
                        if widget.type == .cloudCoverCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Display Style")
                                    .font(.subheadline)
                                    .foregroundColor(theme.textColor.opacity(0.7))
                                    .padding(.horizontal)
                                Picker("Style", selection: Binding(
                                    get: { widget.config?["style"] ?? "standard" },
                                    set: { newValue in
                                        if widget.config == nil { widget.config = [:] }
                                        widget.config?["style"] = newValue
                                    }
                                )) {
                                    Text("Compact").tag("compact")
                                    Text("Standard").tag("standard")
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal)
                            }
                        }
                        
                        if widget.type == .minutePrecipitation {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Time Range")
                                    .font(.subheadline)
                                    .foregroundColor(theme.textColor.opacity(0.7))
                                    .padding(.horizontal)
                                Picker("Range", selection: Binding(
                                    get: { widget.config?["rangeMinutes"] ?? "60" },
                                    set: { newValue in
                                        if widget.config == nil { widget.config = [:] }
                                        widget.config?["rangeMinutes"] = newValue
                                    }
                                )) {
                                    Text("30 min").tag("30")
                                    Text("60 min").tag("60")
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal)
                            }
                        }
                        
                        if widget.type == .windGraph {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Forecast Range")
                                    .font(.subheadline)
                                    .foregroundColor(theme.textColor.opacity(0.7))
                                    .padding(.horizontal)
                                Picker("Range", selection: Binding(
                                    get: { widget.config?["rangeHours"] ?? "24" },
                                    set: { newValue in
                                        if widget.config == nil { widget.config = [:] }
                                        widget.config?["rangeHours"] = newValue
                                    }
                                )) {
                                    Text("12 hr").tag("12")
                                    Text("24 hr").tag("24")
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal)
                            }
                        }
                        
                        if widget.type == .dailyForecast {
                            VStack(alignment: .leading, spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Day Range")
                                        .font(.subheadline)
                                        .foregroundColor(theme.textColor.opacity(0.7))
                                        .padding(.horizontal)
                                    Picker("Days", selection: Binding(
                                        get: { widget.config?["rangeDays"] ?? "10" },
                                        set: { newValue in
                                            if widget.config == nil { widget.config = [:] }
                                            widget.config?["rangeDays"] = newValue
                                        }
                                    )) {
                                        Text("5 days").tag("5")
                                        Text("7 days").tag("7")
                                        Text("10 days").tag("10")
                                    }
                                    .pickerStyle(.segmented)
                                    .padding(.horizontal)
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Condition Icons")
                                        .font(.subheadline)
                                        .foregroundColor(theme.textColor.opacity(0.7))
                                        .padding(.horizontal)
                                    Picker("Icons", selection: Binding(
                                        get: { widget.config?["showIcons"] ?? "true" },
                                        set: { newValue in
                                            if widget.config == nil { widget.config = [:] }
                                            widget.config?["showIcons"] = newValue
                                        }
                                    )) {
                                        Text("Show").tag("true")
                                        Text("Hide").tag("false")
                                    }
                                    .pickerStyle(.segmented)
                                    .padding(.horizontal)
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

// MARK: - Share Weather Card

struct ShareWeatherCardView: View {
    let weather: WeatherInfo
    @ObservedObject var viewModel: WeatherViewModel
    let colorScheme: ColorScheme
    @Environment(\.dismiss) var dismiss
    @State private var renderedImage: Image?
    
    private var theme: WeatherTheme {
        viewModel.currentTheme(colorScheme: colorScheme)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground(colors: [theme.topColor, theme.bottomColor])
                
                VStack(spacing: 24) {
                    Spacer()
                    
                    shareCardContent
                        .padding(.horizontal, 24)
                    
                    Spacer()
                    
                    if let renderedImage {
                        renderedImage
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(radius: 10)
                    }
                    
                    ShareLink(
                        item: renderedImage ?? Image(systemName: "photo"),
                        preview: SharePreview("Weather in \(weather.location.city)", image: renderedImage ?? Image(systemName: "photo"))
                    ) {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Share")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .foregroundStyle(theme.textColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
                        )
                        .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(theme.textColor)
                        .fontWeight(.bold)
                }
            }
            .task { renderCard() }
        }
    }
    
    private var shareCardContent: some View {
        VStack(spacing: 16) {
            HStack {
                Text(weather.location.city)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.textColor.opacity(0.7))
                Spacer()
                Text(Date(), style: .date)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textColor.opacity(0.5))
            }
            
            HStack(alignment: .center, spacing: 16) {
                if viewModel.useMinimalistIcons {
                    Image(systemName: WeatherIconHelper.minimalistIcon(for: weather.condition))
                        .font(.system(size: 48))
                        .foregroundStyle(theme.textColor)
                } else {
                    Text(weather.emoji)
                        .font(.system(size: 48))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(weather.temperature)
                        .font(.system(size: 52, weight: .thin, design: viewModel.typography.design))
                        .foregroundStyle(theme.textColor)
                    
                    Text(weather.condition)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(theme.textColor.opacity(0.85))
                }
                
                Spacer()
            }
            
            if let high = weather.highTemp, let low = weather.lowTemp {
                HStack(spacing: 24) {
                    Label(high, systemImage: "arrow.up")
                        .font(.subheadline.weight(.medium))
                    Label(low, systemImage: "arrow.down")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(theme.textColor.opacity(0.6))
            }
            
            if let feelsLike = weather.feelsLike {
                Text("Feels like \(feelsLike)")
                    .font(.caption)
                    .foregroundStyle(theme.textColor.opacity(0.5))
            }
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(theme.textColor.opacity(0.15), lineWidth: 1)
                )
        )
        .background(
            ImageRendererView(content: AnyView(shareCardRenderable))
                .opacity(0)
        )
    }
    
    @ViewBuilder
    private var shareCardRenderable: some View {
        ZStack {
            LinearGradient(
                colors: [theme.topColor, theme.bottomColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: 400, height: 300)
            .ignoresSafeArea()
            
            VStack(spacing: 16) {
                HStack {
                    Text(weather.location.city)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.textColor.opacity(0.7))
                    Spacer()
                    Text(Date(), style: .date)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textColor.opacity(0.5))
                }
                
                HStack(alignment: .center, spacing: 16) {
                    if viewModel.useMinimalistIcons {
                        Image(systemName: WeatherIconHelper.minimalistIcon(for: weather.condition))
                            .font(.system(size: 48))
                            .foregroundStyle(theme.textColor)
                    } else {
                        Text(weather.emoji)
                            .font(.system(size: 48))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(weather.temperature)
                            .font(.system(size: 52, weight: .thin))
                            .foregroundStyle(theme.textColor)
                        
                        Text(weather.condition)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(theme.textColor.opacity(0.85))
                    }
                    
                    Spacer()
                }
                
                if let high = weather.highTemp, let low = weather.lowTemp {
                    HStack(spacing: 24) {
                        Label(high, systemImage: "arrow.up")
                            .font(.subheadline.weight(.medium))
                        Label(low, systemImage: "arrow.down")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(theme.textColor.opacity(0.6))
                }
                
                HStack {
                    Spacer()
                    Text("Breezy")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textColor.opacity(0.3))
                }
            }
            .padding(28)
        }
    }
    
    private func renderCard() {
        let renderer = ImageRenderer(content: shareCardRenderable)
        renderer.scale = 3.0
        if let uiImage = renderer.uiImage {
            renderedImage = Image(uiImage: uiImage)
        }
    }
}

struct ImageRendererView: View {
    let content: AnyView
    var body: some View { content }
}
