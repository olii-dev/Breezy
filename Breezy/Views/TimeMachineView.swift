//
//  TimeMachineView.swift
//  Breezy
//
//  Time Machine - Historical Weather Comparison
//

import SwiftUI
import Charts

struct TimeMachineView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @State private var date1 = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var date2 = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    @State private var viewMode: ViewMode = .details
    @AppStorage("Breezy.timeMachine.date1") private var storedDate1Epoch: Double = Date().addingTimeInterval(-7 * 86_400).timeIntervalSince1970
    @AppStorage("Breezy.timeMachine.date2") private var storedDate2Epoch: Double = Date().addingTimeInterval(-1 * 86_400).timeIntervalSince1970
    
    // View Mode Selection - Details and Compare
    enum ViewMode: String, CaseIterable {
        case details = "Details"
        case compare = "Compare"
        
        var icon: String {
            switch self {
            case .details: return "calendar.badge.clock"
            case .compare: return "arrow.left.arrow.right"
            }
        }
    }
    
    private var theme: WeatherTheme {
        viewModel.currentTheme(colorScheme: colorScheme)
    }
    
    private var backgroundGradient: some View {
        AnimatedGradientBackground(
            colors: [theme.topColor, theme.bottomColor]
        )
        .ignoresSafeArea()
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                
                ScrollView {
                    VStack(spacing: 24) {
                        // HEADER
                        Text("TIME MACHINE")
                            .font(.system(size: 22, weight: .bold, design: viewModel.typography.design))
                            .tracking(3)
                            .foregroundStyle(theme.textColor)
                            .padding(.top, 8)
                        
                        // MODE SELECTOR
                        HStack(spacing: 12) {
                            ForEach(ViewMode.allCases, id: \.self) { mode in
                                Button {
                                    withAnimation(.spring(response: 0.3)) {
                                        viewMode = mode
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: mode.icon)
                                            .font(.headline)
                                        Text(mode.rawValue)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                    }
                                    .foregroundStyle(viewMode == mode ? theme.topColor : theme.textColor.opacity(0.7))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(viewMode == mode ? Color.white.opacity(0.95) : Color.white.opacity(0.12))
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // CONTENT BASED ON MODE
                        if viewMode == .details {
                            detailsModeView
                        } else {
                            compareModeView
                        }
                        
                        // Error State
                        if let error = viewModel.historicalError {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.largeTitle)
                                    .foregroundStyle(theme.textColor)
                                Text(error)
                                    .font(.subheadline)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(theme.textColor.opacity(0.8))
                            }
                            .padding(20)
                            .background(Color.red.opacity(0.15))
                            .cornerRadius(16)
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(theme.textColor.opacity(0.7))
                            .font(.title3)
                    }
                }
            }
            .onAppear {
                let rememberedDate1 = Date(timeIntervalSince1970: storedDate1Epoch)
                let rememberedDate2 = Date(timeIntervalSince1970: storedDate2Epoch)
                date1 = rememberedDate1
                date2 = rememberedDate2
            }
            .onChange(of: date1) { _, newValue in
                storedDate1Epoch = newValue.timeIntervalSince1970
            }
            .onChange(of: date2) { _, newValue in
                storedDate2Epoch = newValue.timeIntervalSince1970
            }
        }
    }
    
    // MARK: - Details Mode View
    
    @ViewBuilder
    private var detailsModeView: some View {
        VStack(spacing: 16) {
            // Date Picker
            HStack(spacing: 12) {
                DatePicker("", selection: $date1, in: (Calendar.current.date(from: DateComponents(year: 2021, month: 8, day: 1)) ?? Date.distantPast)...Date(), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .tint(theme.textColor)
                    .labelsHidden()
                
                Button {
                    Task {
                        await viewModel.fetchHistoricalWeather(for: date1, slot: 1)
                    }
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.historicalLoading {
                            ProgressView()
                                .tint(theme.textColor)
                        } else {
                            Image(systemName: "arrow.clockwise")
                            Text("Fetch")
                        }
                    }
                    .foregroundStyle(theme.textColor)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
                    )
                }
                .disabled(viewModel.historicalLoading)
            }
            .padding(16)
            .softGlassCard(padding: 16, cornerRadius: 16)
            .padding(.horizontal, 20)
            
            // Weather Display
            if let history = viewModel.historicalWeather {
                VStack(spacing: 20) {
                    // MAIN CARD
                    VStack(spacing: 12) {
                        Text(viewModel.dateFormat.format(date1).uppercased())
                            .font(.caption.weight(.bold))
                            .tracking(1.5)
                            .foregroundStyle(theme.textColor.opacity(0.5))
                        
                        HStack(alignment: .center, spacing: 16) {
                            if viewModel.useMinimalistIcons {
                                Image(systemName: WeatherIconHelper.minimalistIcon(for: history.condition))
                                    .font(.system(size: 54))
                                    .foregroundStyle(theme.textColor)
                            } else {
                                Text(history.emoji)
                                    .font(.system(size: 54))
                            }
                            
                            Text(history.temperature)
                                .font(.system(size: 64, weight: .thin))
                                .foregroundStyle(theme.textColor)
                        }
                        
                        Text(history.condition)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(theme.textColor.opacity(0.95))
                        
                        if let high = history.highTemp, let low = history.lowTemp {
                            HStack(spacing: 20) {
                                Label(high, systemImage: "arrow.up")
                                    .font(.subheadline.weight(.medium))
                                Label(low, systemImage: "arrow.down")
                                    .font(.subheadline.weight(.medium))
                            }
                            .foregroundStyle(theme.textColor.opacity(0.65))
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .softGlassCard(padding: 0, cornerRadius: 20)
                    
                    // SUN TIMES (if available)
                    if let metrics = history.metrics,
                       let sunrise = metrics.sunrise,
                       let sunset = metrics.sunset {
                        HStack(spacing: 12) {
                            TMSunTimeCard(icon: "sunrise.fill", label: "Sunrise", time: sunrise, theme: theme, viewModel: viewModel)
                            TMSunTimeCard(icon: "sunset.fill", label: "Sunset", time: sunset, theme: theme, viewModel: viewModel)
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // INTERACTIVE HOURLY HISTORY
                    if !history.hourlyForecast.isEmpty {
                        TimeMachineHourlyChartView(history: history, theme: theme, viewModel: viewModel)
                            .padding(.horizontal, 20)
                    }
                    
                    // METRICS GRID
                    if let metrics = history.metrics {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("DETAILS")
                                .font(.caption.weight(.bold))
                                .tracking(1.5)
                                .foregroundStyle(theme.textColor.opacity(0.5))
                                .padding(.horizontal, 20)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                if let windSpeed = metrics.windSpeed {
                                    EnhancedMetricCard(icon: "wind", label: "Wind", value: windSpeed, subValue: metrics.windDirectionCardinal ?? "", theme: theme, viewModel: viewModel)
                                }
                                if let uv = metrics.uvIndex {
                                    EnhancedMetricCard(icon: "sun.max.fill", label: "UV Index", value: "\(uv)", subValue: metrics.uvIndexCategory ?? "", theme: theme, viewModel: viewModel)
                                }
                                if let humidity = metrics.humidity {
                                    EnhancedMetricCard(icon: "humidity", label: "Humidity", value: "\(humidity)%", subValue: "", theme: theme, viewModel: viewModel)
                                }
                                if let rain = metrics.rainChance {
                                    EnhancedMetricCard(icon: "drop.fill", label: "Rain", value: rain, subValue: "", theme: theme, viewModel: viewModel)
                                }
                                if let pressure = metrics.pressure {
                                    EnhancedMetricCard(icon: "gauge.medium", label: "Pressure", value: pressure, subValue: "", theme: theme, viewModel: viewModel)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
    }
    
    // MARK: - Compare Mode View
    
    @ViewBuilder
    private var compareModeView: some View {
        VStack(spacing: 20) {
            // DATE SELECTION
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Date 1")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(theme.textColor.opacity(0.5))
                        DatePicker("", selection: $date1, in: (Calendar.current.date(from: DateComponents(year: 2021, month: 8, day: 1)) ?? Date.distantPast)...Date(), displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .tint(theme.textColor)
                            .labelsHidden()
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Date 2")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(theme.textColor.opacity(0.5))
                        DatePicker("", selection: $date2, in: (Calendar.current.date(from: DateComponents(year: 2021, month: 8, day: 1)) ?? Date.distantPast)...Date(), displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .tint(theme.textColor)
                            .labelsHidden()
                    }
                }
                
                Button {
                    Task {
                        await viewModel.fetchHistoricalWeather(for: date1, slot: 1)
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        await viewModel.fetchHistoricalWeather(for: date2, slot: 2)
                    }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.historicalLoading {
                            ProgressView()
                                .tint(theme.textColor)
                        } else {
                            Image(systemName: "arrow.left.arrow.right.circle.fill")
                            Text("Compare Dates")
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundStyle(theme.textColor)
                    .font(.subheadline)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
                    )
                }
                .disabled(viewModel.historicalLoading)
            }
            .padding(16)
                .softGlassCard(padding: 0, cornerRadius: 16)
            .padding(.horizontal, 20)
            
            // COMPARISON DISPLAY
            if let weather1 = viewModel.historicalWeather, let weather2 = viewModel.historicalWeather2 {
                VStack(spacing: 20) {
                    // Side-by-side cards
                    HStack(spacing: 12) {
                        EnhancedComparisonCard(
                            date: date1,
                            weather: weather1,
                            dateFormat: viewModel.dateFormat,
                            useIcon: viewModel.useMinimalistIcons,
                            theme: theme,
                            viewModel: viewModel
                        )
                        
                        EnhancedComparisonCard(
                            date: date2,
                            weather: weather2,
                            dateFormat: viewModel.dateFormat,
                            useIcon: viewModel.useMinimalistIcons,
                            theme: theme,
                            viewModel: viewModel
                        )
                    }
                    .padding(.horizontal, 20)
                    
                    // Sun times comparison
                    if let m1 = weather1.metrics, let m2 = weather2.metrics,
                       let sr1 = m1.sunrise, let ss1 = m1.sunset,
                       let sr2 = m2.sunrise, let ss2 = m2.sunset {
                        VStack(spacing: 8) {
                            SunComparisonRow(icon: "sunrise.fill", label: "Sunrise", time1: sr1, time2: sr2, theme: theme, viewModel: viewModel)
                            SunComparisonRow(icon: "sunset.fill", label: "Sunset", time1: ss1, time2: ss2, theme: theme, viewModel: viewModel)
                        }
                        .padding(16)
                        .softGlassCard(padding: 0, cornerRadius: 16)
                        .padding(.horizontal, 20)
                    }
                    
                    // Metrics comparison
                    EnhancedComparisonMetrics(
                        date1: date1,
                        date2: date2,
                        weather1: weather1,
                        weather2: weather2,
                        theme: theme,
                        viewModel: viewModel
                    )
                        .padding(.horizontal, 20)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 56))
                        .foregroundStyle(theme.textColor.opacity(0.3))
                    
                    Text("Select two dates to compare")
                        .font(.subheadline)
                        .foregroundStyle(theme.textColor.opacity(0.5))
                }
                .padding(.vertical, 60)
            }
        }
    }
}

// MARK: - Sun Time Card

struct TMSunTimeCard: View {
    let icon: String
    let label: String
    let time: String
    let theme: WeatherTheme
    let viewModel: WeatherViewModel
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(theme.textColor.opacity(0.6))
                Text(time)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textColor)
            }
            
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .softGlassCard(padding: 0, cornerRadius: 14)
    }
}

// MARK: - Interactive Historical Hourly Chart

struct TimeMachineHourlyChartView: View {
    let history: WeatherInfo
    let theme: WeatherTheme
    @ObservedObject var viewModel: WeatherViewModel
    @State private var selectedHourID: String?

    private var hours: [HourlyForecast] {
        Array(history.hourlyForecast.prefix(24))
            .sorted { lhs, rhs in
                if lhs.hourValue == rhs.hourValue {
                    return (lhs.sourceDate ?? .distantPast) < (rhs.sourceDate ?? .distantPast)
                }
                return lhs.hourValue < rhs.hourValue
            }
    }

    private var selectedHour: HourlyForecast? {
        guard let selectedHourID else { return nil }
        return hours.first { $0.id == selectedHourID }
    }

    private var range: ClosedRange<Double> {
        let values = hours.map { $0.temperatureRaw }
        guard let minVal = values.min(), let maxVal = values.max() else { return 0...1 }
        let padding = max(1.5, (maxVal - minVal) * 0.2)
        return (minVal - padding)...(maxVal + padding)
    }

    private var labelHours: [Int] {
        [0, 6, 12, 18].filter { hour in
            hours.contains(where: { $0.hourValue == hour })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HOURLY HISTORY")
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(theme.textColor.opacity(0.5))

            Chart {
                ForEach(hours) { hour in
                    AreaMark(
                        x: .value("Hour", hour.hourValue),
                        yStart: .value("Base", range.lowerBound),
                        yEnd: .value("Temperature", hour.temperatureRaw)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [theme.textColor.opacity(0.28), theme.textColor.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Hour", hour.hourValue),
                        y: .value("Temperature", hour.temperatureRaw)
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .foregroundStyle(theme.textColor.opacity(0.9))

                    PointMark(
                        x: .value("Hour", hour.hourValue),
                        y: .value("Temperature", hour.temperatureRaw)
                    )
                    .symbolSize(selectedHourID == hour.id ? 56 : 18)
                    .foregroundStyle(theme.textColor.opacity(selectedHourID == hour.id ? 1.0 : 0.65))
                }

                if let selectedHour {
                    RuleMark(x: .value("Selected", selectedHour.hourValue))
                        .foregroundStyle(theme.textColor.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(selectedHour.time) · \(viewModel.formattedTemperature(selectedHour.temperatureRaw))")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(theme.textColor)

                                HStack(spacing: 8) {
                                    if let rain = selectedHour.precipitationChance {
                                        TMTooltipChip(label: "Rain", value: "\(Int(rain * 100))%")
                                    }
                                    if let humidity = selectedHour.humidity {
                                        TMTooltipChip(label: "Hum", value: "\(humidity)%")
                                    }
                                    if let uv = selectedHour.uvIndex {
                                        TMTooltipChip(label: "UV", value: "\(uv)")
                                    }
                                }

                                if let wind = selectedHour.windSpeed, !wind.isEmpty {
                                    Text("Wind \(wind)\(selectedHour.windDirection.map { " · \($0)" } ?? "")")
                                        .font(.caption2)
                                        .foregroundColor(theme.textColor.opacity(0.72))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(theme.textColor.opacity(0.12), lineWidth: 0.5)
                            )
                        }
                }
            }
            .frame(height: 240)
            .chartXScale(domain: 0...23)
            .chartYScale(domain: range)
            .chartXAxis {
                AxisMarks(values: labelHours) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                        .foregroundStyle(theme.textColor.opacity(0.12))
                    AxisValueLabel {
                        if let hour = value.as(Int.self) {
                            Text(DateFormatterHelper.formatHour(hour))
                                .font(.caption2)
                                .foregroundStyle(theme.textColor.opacity(0.7))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                        .foregroundStyle(theme.textColor.opacity(0.1))
                    AxisValueLabel {
                        if let temperature = value.as(Double.self) {
                            Text(viewModel.formattedTemperature(temperature))
                                .font(.caption2)
                                .foregroundStyle(theme.textColor.opacity(0.6))
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    guard !hours.isEmpty else { return }
                                    guard let plotFrame = proxy.plotFrame else { return }
                                    let frame = geometry[plotFrame]
                                    let x = min(max(value.location.x - frame.minX, 0), frame.width)
                                    let ratio = frame.width > 0 ? x / frame.width : 0
                                    let targetHour = Int(round(ratio * 23))

                                    let nearest = hours.min { a, b in
                                        abs(a.hourValue - targetHour) < abs(b.hourValue - targetHour)
                                    }
                                    if let nearest, nearest.id != selectedHourID {
                                        HapticsManager.shared.impact(style: .light)
                                        selectedHourID = nearest.id
                                    }
                                }
                                .onEnded { _ in
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                        selectedHourID = nil
                                    }
                                }
                        )
                }
            }
        }
        .padding(16)
        .softGlassCard(padding: 0, cornerRadius: 18)
    }
}

private struct TMTooltipChip: View {
    let label: String
    let value: String

    var body: some View {
        Text("\(label) \(value)")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.12), in: Capsule())
    }
}

// MARK: - Hourly Card

struct HourlyCard: View {
    let hour: HourlyForecast
    let useIcon: Bool
    let theme: WeatherTheme
    let viewModel: WeatherViewModel
    
    var body: some View {
        VStack(spacing: 8) {
            Text(hour.time)
                .font(.caption2.weight(.medium))
                .foregroundStyle(theme.textColor.opacity(0.6))
            
            if useIcon {
                Image(systemName: WeatherIconHelper.minimalistIcon(for: hour.condition ?? "Clear"))
                    .font(.title3)
                    .foregroundStyle(theme.textColor)
            } else {
                Text(hour.emoji ?? "--")
                    .font(.title3)
            }
            
            Text("\(Int(hour.temperatureRaw))°")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textColor)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .softGlassCard(padding: 0, cornerRadius: 14)
    }
}

// MARK: - Enhanced Metric Card

struct EnhancedMetricCard: View {
    let icon: String
    let label: String
    let value: String
    let subValue: String
    let theme: WeatherTheme
    let viewModel: WeatherViewModel

    init(icon: String, label: String, value: String, subValue: String, theme: WeatherTheme, viewModel: WeatherViewModel) {
        self.icon = icon
        self.label = label
        self.value = value
        self.subValue = subValue
        self.theme = theme
        self.viewModel = viewModel
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon)
                .font(.caption2.weight(.medium))
                .foregroundStyle(theme.textColor.opacity(0.6))
            
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.textColor)
            
            if !subValue.isEmpty {
                Text(subValue)
                    .font(.caption2)
                    .foregroundStyle(theme.textColor.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .softGlassCard(padding: 0, cornerRadius: 14)
    }
}

// MARK: - Enhanced Comparison Card

struct EnhancedComparisonCard: View {
    let date: Date
    let weather: WeatherInfo
    let dateFormat: DateFormat
    let useIcon: Bool
    let theme: WeatherTheme
    let viewModel: WeatherViewModel

    init(date: Date, weather: WeatherInfo, dateFormat: DateFormat, useIcon: Bool, theme: WeatherTheme, viewModel: WeatherViewModel) {
        self.date = date
        self.weather = weather
        self.dateFormat = dateFormat
        self.useIcon = useIcon
        self.theme = theme
        self.viewModel = viewModel
    }
    
    var body: some View {
        VStack(spacing: 10) {
            Text(dateFormat.format(date))
                .font(.caption2.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(theme.textColor.opacity(0.5))
            
            if useIcon {
                Image(systemName: WeatherIconHelper.minimalistIcon(for: weather.condition))
                    .font(.system(size: 44))
                    .foregroundStyle(theme.textColor)
            } else {
                Text(weather.emoji)
                    .font(.system(size: 44))
            }
            
            Text(weather.temperature)
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(theme.textColor)
            
            Text(weather.condition)
                .font(.caption.weight(.medium))
                .foregroundStyle(theme.textColor.opacity(0.75))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            
            if let high = weather.highTemp, let low = weather.lowTemp {
                HStack(spacing: 10) {
                    Text("↑\(high)")
                    Text("↓\(low)")
                }
                .font(.caption2)
                .foregroundStyle(theme.textColor.opacity(0.6))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .softGlassCard(padding: 0, cornerRadius: 18)
    }
}

// MARK: - Sun Comparison Row

struct SunComparisonRow: View {
    let icon: String
    let label: String
    let time1: String
    let time2: String
    let theme: WeatherTheme
    let viewModel: WeatherViewModel

    init(icon: String, label: String, time1: String, time2: String, theme: WeatherTheme, viewModel: WeatherViewModel) {
        self.icon = icon
        self.label = label
        self.time1 = time1
        self.time2 = time2
        self.theme = theme
        self.viewModel = viewModel
    }
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.orange)
                .frame(width: 24)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(theme.textColor.opacity(0.7))
            
            Spacer()
            
            Text(time1)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(theme.textColor.opacity(0.7))
            
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(theme.textColor.opacity(viewModel.glassOpacity))
            
            Text(time2)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(theme.textColor)
        }
    }
}

// MARK: - Enhanced Comparison Metrics

struct EnhancedComparisonMetrics: View {
    let date1: Date
    let date2: Date
    let weather1: WeatherInfo
    let weather2: WeatherInfo
    let theme: WeatherTheme
    let viewModel: WeatherViewModel

    init(date1: Date, date2: Date, weather1: WeatherInfo, weather2: WeatherInfo, theme: WeatherTheme, viewModel: WeatherViewModel) {
        self.date1 = date1
        self.date2 = date2
        self.weather1 = weather1
        self.weather2 = weather2
        self.theme = theme
        self.viewModel = viewModel
    }
    
    var body: some View {
        VStack(spacing: 16) {
            let temp1 = numericValue(from: weather1.temperature)
            let temp2 = numericValue(from: weather2.temperature)

            if let temp1, let temp2 {
                TMComparisonTrend(
                    title: "Temperature Trend",
                    value1: temp1,
                    value2: temp2,
                    label1: viewModel.dateFormat.format(date1),
                    label2: viewModel.dateFormat.format(date2),
                    theme: theme,
                    viewModel: viewModel
                )
            }

            let metrics1 = weather1.metrics
            let metrics2 = weather2.metrics

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if let temp1, let temp2 {
                    TMDeltaCard(
                        icon: "thermometer.medium",
                        label: "Temperature",
                        value1: weather1.temperature,
                        value2: weather2.temperature,
                        delta: temp2 - temp1,
                        suffix: viewModel.temperatureUnit.symbol,
                        theme: theme,
                        viewModel: viewModel
                    )
                }

                if let humidity1 = metrics1?.humidity, let humidity2 = metrics2?.humidity {
                    TMDeltaCard(
                        icon: "humidity",
                        label: "Humidity",
                        value1: "\(humidity1)%",
                        value2: "\(humidity2)%",
                        delta: Double(humidity2 - humidity1),
                        suffix: "%",
                        theme: theme,
                        viewModel: viewModel
                    )
                }

                if let uv1 = metrics1?.uvIndex, let uv2 = metrics2?.uvIndex {
                    TMDeltaCard(
                        icon: "sun.max.fill",
                        label: "UV Index",
                        value1: "\(uv1)",
                        value2: "\(uv2)",
                        delta: Double(uv2 - uv1),
                        suffix: "",
                        theme: theme,
                        viewModel: viewModel
                    )
                }

                if let rain1 = metrics1?.rainChance, let rain2 = metrics2?.rainChance,
                   let rainValue1 = numericValue(from: rain1), let rainValue2 = numericValue(from: rain2) {
                    TMDeltaCard(
                        icon: "drop.fill",
                        label: "Rain Chance",
                        value1: rain1,
                        value2: rain2,
                        delta: rainValue2 - rainValue1,
                        suffix: "%",
                        theme: theme,
                        viewModel: viewModel
                    )
                }

                if let pressure1 = metrics1?.pressure, let pressure2 = metrics2?.pressure,
                   let pressureValue1 = numericValue(from: pressure1), let pressureValue2 = numericValue(from: pressure2) {
                    TMDeltaCard(
                        icon: "gauge.medium",
                        label: "Pressure",
                        value1: pressure1,
                        value2: pressure2,
                        delta: pressureValue2 - pressureValue1,
                        suffix: "",
                        theme: theme,
                        viewModel: viewModel
                    )
                }

                if let wind1 = metrics1?.windSpeed, let wind2 = metrics2?.windSpeed,
                   let windValue1 = numericValue(from: wind1), let windValue2 = numericValue(from: wind2) {
                    TMDeltaCard(
                        icon: "wind",
                        label: "Wind",
                        value1: wind1,
                        value2: wind2,
                        delta: windValue2 - windValue1,
                        suffix: "",
                        theme: theme,
                        viewModel: viewModel
                    )
                }
            }
        }
    }

    private func numericValue(from text: String) -> Double? {
        let filtered = text.filter { $0.isNumber || $0 == "." || $0 == "-" }
        return Double(filtered)
    }
}

private struct TMDeltaCard: View {
    let icon: String
    let label: String
    let value1: String
    let value2: String
    let delta: Double
    let suffix: String
    let theme: WeatherTheme
    let viewModel: WeatherViewModel

    private var deltaColor: Color {
        if delta > 0 { return .red.opacity(0.9) }
        if delta < 0 { return .blue.opacity(0.9) }
        return theme.textColor.opacity(0.6)
    }

    private var deltaLabel: String {
        if delta == 0 { return "No change" }
        let sign = delta > 0 ? "+" : ""
        let rounded = abs(delta) >= 10 ? String(Int(delta)) : String(format: "%.1f", delta)
        return "\(sign)\(rounded)\(suffix)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(theme.textColor.opacity(0.65))

            HStack(spacing: 8) {
                Text(value1)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.textColor.opacity(0.7))

                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(theme.textColor.opacity(0.45))

                Text(value2)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.textColor)
            }

            Text(deltaLabel)
                .font(.headline.weight(.bold))
                .foregroundStyle(deltaColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .softGlassCard(padding: 0, cornerRadius: 14)
    }
}

private struct TMComparisonTrend: View {
    let title: String
    let value1: Double
    let value2: Double
    let label1: String
    let label2: String
    let theme: WeatherTheme
    let viewModel: WeatherViewModel

    private var maxValue: Double {
        max(max(value1, value2), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.textColor.opacity(0.6))

            HStack(alignment: .bottom, spacing: 18) {
                trendBar(value: value1, label: label1)
                trendBar(value: value2, label: label2)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .softGlassCard(padding: 0, cornerRadius: 14)
    }

    private func trendBar(value: Double, label: String) -> some View {
        VStack(spacing: 6) {
            Text(viewModel.formattedTemperature(value))
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.textColor)

            RoundedRectangle(cornerRadius: 5)
                .fill(theme.textColor.opacity(0.65))
                .frame(width: 34, height: max(20, CGFloat(value / maxValue) * 86))

            Text(label)
                .font(.caption2)
                .foregroundStyle(theme.textColor.opacity(0.65))
        }
    }
}

// MARK: - Comparison Metric Row

struct ComparisonMetricRow: View {
    let icon: String
    let label: String
    let value1: String
    let value2: String
    let delta: Int
    let unit: String
    let theme: WeatherTheme
    let viewModel: WeatherViewModel

    init(icon: String, label: String, value1: String, value2: String, delta: Int, unit: String, theme: WeatherTheme, viewModel: WeatherViewModel) {
        self.icon = icon
        self.label = label
        self.value1 = value1
        self.value2 = value2
        self.delta = delta
        self.unit = unit
        self.theme = theme
        self.viewModel = viewModel
    }
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(theme.textColor.opacity(0.6))
                .frame(width: 20)
            
            Text(label)
                .font(.caption)
                .foregroundStyle(theme.textColor.opacity(0.7))
            
            Spacer()
            
            Text(value1)
                .font(.caption)
                .foregroundStyle(theme.textColor.opacity(0.6))
            
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundStyle(theme.textColor.opacity(viewModel.glassOpacity))
            
            Text(value2)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(theme.textColor)
            
            if delta != 0 {
                Text("(\(delta > 0 ? "+" : "")\(delta)\(unit))")
                    .font(.caption2)
                    .foregroundStyle(delta > 0 ? .red : .blue)
            }
        }
    }
}

// Backwards compatibility components
typealias TimeMachineMetricCard = EnhancedMetricCard
typealias WeatherComparisonCard = EnhancedComparisonCard
typealias ComparisonMetrics = EnhancedComparisonMetrics
typealias ComparisonRow = ComparisonMetricRow
