//
//  MacDashboardView.swift
//  BreezyMac
//
//  The themed weather dashboard: header + adaptive card grid driven by the
//  same DashboardWidget store the iPhone app uses (synced via iCloud KV).
//

import SwiftUI

struct MacDashboardView: View {
    @ObservedObject var viewModel: WeatherViewModel
    var locationHelper: LocationHelper? = nil
    var onPickLocation: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme

    @State private var dashboardWidgets: [DashboardWidget] = DashboardWidget.defaultDashboard
    @State private var isEditMode = false
    @State private var isInteractingWithChart = false
    @State private var showingWidgetGallery = false
    @State private var widgetBeingConfigured: DashboardWidget?
    @State private var widgetPendingRemoval: DashboardWidget?
    @State private var showShareCard = false
    @State private var showRadar = false

    private var theme: WeatherTheme {
        viewModel.currentTheme(colorScheme: colorScheme)
    }

    private let columns = [GridItem(.adaptive(minimum: 400, maximum: 560), spacing: DesignSystem.spacingL)]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DesignSystem.spacingXL) {
                header
                controlBar
                cardGrid
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 40)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .background(
            PastelGradientBackground(colors: [theme.topColor, theme.bottomColor])
                .ignoresSafeArea()
        )
        .navigationTitle(viewModel.weather?.location.city ?? "Breezy")
        .toolbar { macToolbar }
        .sheet(isPresented: $showingWidgetGallery) {
            WidgetGalleryView(viewModel: viewModel) { type in
                addWidget(type)
            }
        }
        .sheet(item: $widgetBeingConfigured) { item in
            WidgetConfigView(widget: item, viewModel: viewModel) { updated in
                if let index = dashboardWidgets.firstIndex(where: { $0.id == updated.id }) {
                    dashboardWidgets[index] = updated
                    saveDashboard()
                }
            }
        }
        .sheet(isPresented: $showShareCard) {
            ShareWeatherCardView(weather: viewModel.weather!, viewModel: viewModel, colorScheme: colorScheme)
        }
        .sheet(isPresented: $showRadar) {
            FullScreenRadarView(viewModel: viewModel, locationHelper: locationHelper)
        }
        .confirmationDialog(
            "Remove Widget?",
            isPresented: Binding(
                get: { widgetPendingRemoval != nil },
                set: { if !$0 { widgetPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                if let pending = widgetPendingRemoval {
                    withAnimation {
                        dashboardWidgets.removeAll { $0.id == pending.id }
                        saveDashboard()
                    }
                }
                widgetPendingRemoval = nil
            }
        } message: {
            Text("This removes the widget from your dashboard. You can add it back anytime from the gallery.")
        }
        .onAppear {
            loadDashboard()
        }
        .onChange(of: viewModel.weatherSource) { _, _ in
            loadDashboard()
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if let weather = viewModel.weather {
            VStack(spacing: 6) {
                Text(weather.location.city)
                    .font(.title2.weight(.medium))
                    .foregroundColor(theme.textColor.opacity(0.85))

                HStack(alignment: .center, spacing: 18) {
                    Text(weather.temperature)
                        .font(.system(size: 76, weight: .thin, design: viewModel.typography.design))
                        .foregroundColor(theme.textColor)

                    AnimatedWeatherIcon(
                        systemName: viewModel.weatherIcon(for: weather.condition),
                        size: 56,
                        condition: weather.condition,
                        colorScheme: colorScheme
                    )
                }

                Text(weather.condition)
                    .font(.title3.weight(.medium))
                    .foregroundColor(theme.textColor.opacity(0.9))

                if let high = weather.highTemp, let low = weather.lowTemp {
                    Text("H:\(high)  L:\(low)")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(theme.textColor.opacity(0.72))
                }

                if viewModel.isUsingCachedFallback {
                    Text("Showing cached data")
                        .font(.caption)
                        .foregroundColor(theme.textColor.opacity(0.55))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 10) {
            MacDashboardButton(icon: "location.fill", title: viewModel.currentLocation?.city ?? "Location", theme: theme) {
                onPickLocation()
            }
            MacDashboardButton(icon: "square.3.layers.3d.down.right", title: "Radar", theme: theme) {
                showRadar = true
            }
            MacDashboardButton(icon: "hourglass", title: "Time Machine", theme: theme) {
                NotificationCenter.default.post(name: .macTimeMachineRequested, object: nil)
            }
            MacDashboardButton(icon: "square.and.arrow.up", title: "Share", theme: theme) {
                showShareCard = true
            }
            Spacer()
            MacDashboardButton(
                icon: isEditMode ? "checkmark.circle.fill" : "pencil.circle",
                title: isEditMode ? "Done" : "Edit",
                theme: theme,
                prominent: isEditMode
            ) {
                withAnimation(.spring()) {
                    isEditMode.toggle()
                }
            }
        }
    }

    // MARK: - Cards

    @ViewBuilder
    private var cardGrid: some View {
        if let weather = viewModel.weather {
            LazyVGrid(columns: columns, alignment: .center, spacing: DesignSystem.spacingXL) {
                ForEach(dashboardWidgets) { widget in
                    VStack(alignment: .leading, spacing: 0) {
                        if isEditMode {
                            editBadge(for: widget)
                        }
                        renderWidget(widget, weather: weather)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func editBadge(for widget: DashboardWidget) -> some View {
        HStack(spacing: 8) {
            Button {
                moveWidget(widget, by: -1)
            } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.borderless)
            .disabled(dashboardWidgets.first?.id == widget.id)

            Button {
                moveWidget(widget, by: 1)
            } label: {
                Image(systemName: "arrow.down")
            }
            .buttonStyle(.borderless)
            .disabled(dashboardWidgets.last?.id == widget.id)

            Text(widget.type.displayName)
                .font(.caption.weight(.bold))

            Spacer()

            if widget.type.supportsConfiguration {
                Button("Configure") {
                    widgetBeingConfigured = widget
                }
                .buttonStyle(.borderless)
            }
            Button(role: .destructive) {
                widgetPendingRemoval = widget
            } label: {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.borderless)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(.ultraThinMaterial))
    }

    @ToolbarContentBuilder
    private var macToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                onPickLocation()
            } label: {
                Image(systemName: "location.fill")
            }
            .help("Change location")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                NotificationCenter.default.post(name: .macRefreshRequested, object: nil)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
        }
    }

    // MARK: - Widget dispatch (mirrors ContentView.renderWidget)

    @ViewBuilder
    private func renderWidget(_ widget: DashboardWidget, weather: WeatherInfo) -> some View {
        if !widget.type.isSupported(by: viewModel.weatherSource) {
            VStack(spacing: 8) {
                Image(systemName: widget.type.icon)
                    .font(.title2)
                Text(viewModel.weatherSource.capabilities.unsupportedReason(for: widget.type))
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .foregroundColor(theme.textColor.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                    .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
            )
        } else {
            switch widget.type {
            case .hourlyForecast:
                NewHourlyCardView(
                    hourlyData: weather.hourlyForecast,
                    allHourlyData: weather.allHourlyData,
                    viewModel: viewModel,
                    rangeHours: Int(widget.config?["rangeHours"] ?? "24") ?? 24,
                    density: widget.config?["density"] ?? "regular"
                )

            case .dailyForecast:
                NewDailyForecastView(forecast: weather.dailyForecast, viewModel: viewModel, config: widget.config)

            case .forecastNarrative:
                ForecastNarrativeWidget(
                    weather: weather,
                    viewModel: viewModel,
                    showsExpandedDetail: widget.config?["style"] != "compact"
                )

            case .deepDetails:
                if let metrics = weather.metrics {
                    let metricsToUse = widget.visibleMetrics ?? Array(viewModel.visibleMetrics)
                    MetricsPillsView(metrics: metrics, weather: weather, viewModel: viewModel, customMetrics: metricsToUse)
                }

            case .rainSummary:
                RainSummaryWidget(weather: weather, viewModel: viewModel, config: widget.config)

            case .rainfallToday:
                RainfallTodayWidget(weather: weather, viewModel: viewModel, config: widget.config)

            case .windSummary:
                if widget.config?["style"] == "rose", let metrics = weather.metrics {
                    let speedString = metrics.windSpeed?.components(separatedBy: CharacterSet.decimalDigits.inverted).joined() ?? "0"
                    let speed = Double(speedString) ?? 0

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Wind Rose", systemImage: "wind")
                            .font(.caption.weight(.bold))
                            .foregroundColor(theme.textColor.opacity(0.6))
                            .padding(.horizontal)
                            .padding(.top, 16)

                        WindRoseView(
                            speed: speed,
                            direction: metrics.windDirectionCardinal ?? "N",
                            degree: metrics.windDirection ?? 0,
                            color: theme.textColor
                        )
                        .padding(.bottom, 16)
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 8)
                } else {
                    WindSummaryWidget(weather: weather, viewModel: viewModel)
                }

            case .radar:
                RadarCardView(viewModel: viewModel, locationHelper: locationHelper)

            case .smartStack:
                SmartStackWidget(viewModel: viewModel, weather: weather, widget: widget)

            case .uvIndex:
                UVIndexWidget(
                    weather: weather,
                    viewModel: viewModel,
                    style: widget.config?["style"] ?? "standard",
                    showsCategory: (widget.config?["showCategory"] ?? "true") == "true"
                )

            case .feelsLike:
                FeelsLikeWidget(weather: weather, viewModel: viewModel, config: widget.config)

            case .sunPath:
                if let sunrise = weather.metrics?.sunrise, let sunset = weather.metrics?.sunset,
                   let sunriseDate = DateFormatterHelper.parseTime(sunrise, timeZone: TimeZone(identifier: weather.timezone) ?? .current),
                   let sunsetDate = DateFormatterHelper.parseTime(sunset, timeZone: TimeZone(identifier: weather.timezone) ?? .current) {
                    VStack(alignment: .leading, spacing: 0) {
                        Label("Sun Path", systemImage: "sun.max.fill")
                            .font(.caption.weight(.bold))
                            .foregroundColor(theme.textColor.opacity(0.6))
                            .padding(.horizontal)
                            .padding(.top, 16)

                        SunPathView(
                            sunrise: sunriseDate,
                            sunset: sunsetDate,
                            currentTime: Date(),
                            textColor: theme.textColor,
                            style: widget.config?["style"] ?? "full",
                            showsCountdown: (widget.config?["showCountdown"] ?? "true") == "true"
                        )
                        .padding(.top, 16)
                        .padding(.bottom, 16)
                        .padding(.horizontal)
                    }
                }

            case .moonPhase:
                if let today = weather.dailyForecast.first, let phase = today.moonPhase {
                    MoonPhaseCardView(
                        phase: phase,
                        moonrise: today.moonrise,
                        moonset: today.moonset,
                        style: widget.config?["style"] ?? "full",
                        size: widget.config?["size"] ?? "medium",
                        textColor: theme.textColor,
                        glassOpacity: viewModel.glassOpacity,
                        showsDisclosure: false
                    )
                }

            case .uvIndexCurve:
                if let hourly = weather.allHourlyData {
                    VStack(alignment: .leading, spacing: 0) {
                        Label("UV Index", systemImage: "aqi.medium")
                            .font(.caption.weight(.bold))
                            .foregroundColor(theme.textColor.opacity(0.6))
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
                }

            case .windGraph:
                WindGraphWidget(
                    weather: weather,
                    viewModel: viewModel,
                    hoursWindow: Int(widget.config?["rangeHours"] ?? "24") ?? 24,
                    isChartInteracting: $isInteractingWithChart
                )

            case .minutePrecipitation:
                RainGraphWidget(
                    weather: weather,
                    viewModel: viewModel,
                    minuteWindow: Int(widget.config?["rangeMinutes"] ?? "60") ?? 60
                )

            case .hourlyTemperatures:
                HourlyTemperaturesWidget(weather: weather, viewModel: viewModel, isChartInteracting: $isInteractingWithChart, config: widget.config)

            case .humidityStrip:
                HumidityStripWidget(
                    weather: weather,
                    viewModel: viewModel,
                    rangeHours: Int(widget.config?["rangeHours"] ?? "24") ?? 24,
                    isChartInteracting: $isInteractingWithChart
                )

            case .precipitationTimeline:
                PrecipitationTimelineWidget(weather: weather, viewModel: viewModel, config: widget.config)

            case .precipitationAmount:
                HourlyPrecipitationWidget(
                    weather: weather,
                    viewModel: viewModel,
                    rangeHours: Int(widget.config?["rangeHours"] ?? "24") ?? 24,
                    isChartInteracting: $isInteractingWithChart
                )

            case .visibilityCard:
                VisibilityWidget(weather: weather, viewModel: viewModel, config: widget.config)

            case .cloudCoverCard:
                CloudCoverWidget(weather: weather, viewModel: viewModel, config: widget.config)

            case .windHistory:
                WindHistoryWidget(
                    weather: weather,
                    viewModel: viewModel,
                    isChartInteracting: $isInteractingWithChart
                )

            case .airQualityCard:
                AirQualityCardWidget(weather: weather, viewModel: viewModel, config: widget.config)

            case .aqiTrend:
                AQITrendWidget(weather: weather, viewModel: viewModel)

            case .marineOutlook:
                MarineOutlookWidget(weather: weather, viewModel: viewModel, config: widget.config)

            case .surf:
                SurfDashboardCard(weather: weather, viewModel: viewModel, config: widget.config)

            case .pollen:
                PollenDashboardCard(weather: weather, viewModel: viewModel, config: widget.config)

            case .goldenHour:
                GoldenHourWidget(weather: weather, viewModel: viewModel)
            }
        }
    }

    // MARK: - Dashboard store (same keys as the iPhone app)

    private var dashboardStorageKey: String {
        "Breezy.DashboardWidgets.\(viewModel.weatherSource.rawValue)"
    }

    private func loadDashboard() {
        if let data = CloudStorage.shared.data(forKey: dashboardStorageKey),
           let decoded = try? JSONDecoder().decode([DashboardWidget].self, from: data) {
            dashboardWidgets = withNarrativeWidgetIfNeeded(decoded).map { sanitizedWidget($0) }
            return
        }
        dashboardWidgets = DashboardWidget.defaultDashboard
            .filter { $0.type.isSupported(by: viewModel.weatherSource) }
            .map { sanitizedWidget($0) }
    }

    private func saveDashboard() {
        if let encoded = try? JSONEncoder().encode(dashboardWidgets) {
            CloudStorage.shared.set(encoded, forKey: dashboardStorageKey)
        }
    }

    private func addWidget(_ type: WidgetType) {
        let widget = DashboardWidget(id: UUID(), type: type)
        withAnimation {
            dashboardWidgets.append(widget)
        }
        saveDashboard()
    }

    private func moveWidget(_ widget: DashboardWidget, by offset: Int) {
        guard let index = dashboardWidgets.firstIndex(where: { $0.id == widget.id }) else { return }
        let newIndex = index + offset
        guard dashboardWidgets.indices.contains(newIndex) else { return }
        withAnimation {
            dashboardWidgets.swapAt(index, newIndex)
        }
        saveDashboard()
    }

    private func withNarrativeWidgetIfNeeded(_ widgets: [DashboardWidget]) -> [DashboardWidget] {
        guard !widgets.contains(where: { $0.type == .forecastNarrative }) else { return widgets }
        var updated = widgets
        let insertIndex = (updated.firstIndex(where: { $0.type == .dailyForecast }).map { $0 + 1 }) ?? updated.count
        updated.insert(DashboardWidget(id: UUID(), type: .forecastNarrative), at: insertIndex)
        return updated
    }

    private func sanitizedWidget(_ widget: DashboardWidget) -> DashboardWidget {
        var updated = widget
        if widget.type == .smartStack, let configured = widget.config?["widgets"] {
            let supportedTypes = configured
                .split(separator: ",")
                .compactMap { WidgetType(rawValue: String($0)) }
                .filter { $0 != .smartStack && $0 != .radar && $0.isSupported(by: viewModel.weatherSource) }

            let fallback: [WidgetType] = [.uvIndex, .feelsLike, .airQualityCard, .rainSummary]
            var config = updated.config ?? [:]
            config["widgets"] = (supportedTypes.isEmpty ? fallback : supportedTypes)
                .map(\.rawValue)
                .joined(separator: ",")
            updated.config = config
        }
        return updated
    }
}

/// Small glassy toolbar button used in the dashboard control bar.
private struct MacDashboardButton: View {
    let icon: String
    let title: String
    let theme: WeatherTheme
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
            }
            .foregroundColor(theme.textColor.opacity(prominent ? 1.0 : 0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(.ultraThinMaterial.opacity(prominent ? 1.0 : viewModelGlassOpacity))
            )
            .overlay(
                Capsule().stroke(theme.textColor.opacity(prominent ? 0.4 : 0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var viewModelGlassOpacity: Double {
        MacShared.viewModel.glassOpacity
    }
}
