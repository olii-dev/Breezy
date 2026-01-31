//
//  TimeMachineView.swift
//  Breezy
//
//  Time Machine - Historical Weather Comparison
//

import SwiftUI

struct TimeMachineView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @State private var date1 = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var date2 = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    @State private var viewMode: ViewMode = .details
    
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
                            .font(.system(size: 22, weight: .bold, design: .rounded))
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
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(12)
                }
                .disabled(viewModel.historicalLoading)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
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
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.ultraThinMaterial.opacity(0.6))
                    )
                    .padding(.horizontal, 20)
                    
                    // SUN TIMES (if available)
                    if let metrics = history.metrics,
                       let sunrise = metrics.sunrise,
                       let sunset = metrics.sunset {
                        HStack(spacing: 12) {
                            TMSunTimeCard(icon: "sunrise.fill", label: "Sunrise", time: sunrise, theme: theme)
                            TMSunTimeCard(icon: "sunset.fill", label: "Sunset", time: sunset, theme: theme)
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // HOURLY FORECAST
                    if !history.hourlyForecast.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("HOURLY FORECAST")
                                .font(.caption.weight(.bold))
                                .tracking(1.5)
                                .foregroundStyle(theme.textColor.opacity(0.5))
                                .padding(.horizontal, 20)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(history.hourlyForecast.prefix(24)) { hour in
                                        HourlyCard(hour: hour, useIcon: viewModel.useMinimalistIcons, theme: theme)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
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
                                    EnhancedMetricCard(icon: "wind", label: "Wind", value: windSpeed, subValue: metrics.windDirectionCardinal ?? "", theme: theme)
                                }
                                if let uv = metrics.uvIndex {
                                    EnhancedMetricCard(icon: "sun.max.fill", label: "UV Index", value: "\(uv)", subValue: metrics.uvIndexCategory ?? "", theme: theme)
                                }
                                if let humidity = metrics.humidity {
                                    EnhancedMetricCard(icon: "humidity", label: "Humidity", value: "\(humidity)%", subValue: "", theme: theme)
                                }
                                if let rain = metrics.rainChance {
                                    EnhancedMetricCard(icon: "drop.fill", label: "Rain", value: rain, subValue: "", theme: theme)
                                }
                                if let pressure = metrics.pressure {
                                    EnhancedMetricCard(icon: "gauge.medium", label: "Pressure", value: pressure, subValue: "", theme: theme)
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
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(14)
                }
                .disabled(viewModel.historicalLoading)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.1))
            )
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
                            theme: theme
                        )
                        
                        EnhancedComparisonCard(
                            date: date2,
                            weather: weather2,
                            dateFormat: viewModel.dateFormat,
                            useIcon: viewModel.useMinimalistIcons,
                            theme: theme
                        )
                    }
                    .padding(.horizontal, 20)
                    
                    // Sun times comparison
                    if let m1 = weather1.metrics, let m2 = weather2.metrics,
                       let sr1 = m1.sunrise, let ss1 = m1.sunset,
                       let sr2 = m2.sunrise, let ss2 = m2.sunset {
                        VStack(spacing: 8) {
                            SunComparisonRow(icon: "sunrise.fill", label: "Sunrise", time1: sr1, time2: sr2, theme: theme)
                            SunComparisonRow(icon: "sunset.fill", label: "Sunset", time1: ss1, time2: ss2, theme: theme)
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(16)
                        .padding(.horizontal, 20)
                    }
                    
                    // Metrics comparison
                    EnhancedComparisonMetrics(weather1: weather1, weather2: weather2, theme: theme)
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
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial.opacity(0.4))
        )
    }
}

// MARK: - Hourly Card

struct HourlyCard: View {
    let hour: HourlyForecast
    let useIcon: Bool
    let theme: WeatherTheme
    
    var body: some View {
        VStack(spacing: 8) {
            Text(hour.time)
                .font(.caption2.weight(.medium))
                .foregroundStyle(theme.textColor.opacity(0.6))
            
            if useIcon {
                Image(systemName: WeatherIconHelper.minimalistIcon(for: hour.condition))
                    .font(.title3)
                    .foregroundStyle(theme.textColor)
            } else {
                Text(hour.emoji)
                    .font(.title3)
            }
            
            Text("\(Int(hour.temperatureRaw))°")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.textColor)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial.opacity(0.4))
        )
    }
}

// MARK: - Enhanced Metric Card

struct EnhancedMetricCard: View {
    let icon: String
    let label: String
    let value: String
    let subValue: String
    let theme: WeatherTheme
    
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
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial.opacity(0.4))
        )
    }
}

// MARK: - Enhanced Comparison Card

struct EnhancedComparisonCard: View {
    let date: Date
    let weather: WeatherInfo
    let dateFormat: DateFormat
    let useIcon: Bool
    let theme: WeatherTheme
    
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
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial.opacity(0.5))
        )
    }
}

// MARK: - Sun Comparison Row

struct SunComparisonRow: View {
    let icon: String
    let label: String
    let time1: String
    let time2: String
    let theme: WeatherTheme
    
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
                .foregroundStyle(theme.textColor.opacity(0.4))
            
            Text(time2)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(theme.textColor)
        }
    }
}

// MARK: - Enhanced Comparison Metrics

struct EnhancedComparisonMetrics: View {
    let weather1: WeatherInfo
    let weather2: WeatherInfo
    let theme: WeatherTheme
    
    var body: some View {
        VStack(spacing: 16) {
            // Temperature delta
            let temp1Str = weather1.temperature.replacingOccurrences(of: "°", with: "")
            let temp2Str = weather2.temperature.replacingOccurrences(of: "°", with: "")
            if let temp1 = Double(temp1Str),
               let temp2 = Double(temp2Str) {
                let delta = temp2 - temp1
                let deltaStr = delta > 0 ? "+\(Int(delta))°" : "\(Int(delta))°"
                
                HStack(spacing: 12) {
                    Image(systemName: delta > 0 ? "thermometer.sun.fill" : delta < 0 ? "thermometer.snowflake" : "thermometer.medium")
                        .font(.title2)
                        .foregroundStyle(delta > 0 ? .red : delta < 0 ? .blue : theme.textColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Temperature Change")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(theme.textColor.opacity(0.6))
                        Text(deltaStr)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(theme.textColor)
                    }
                    
                    Spacer()
                }
                .padding(16)
                .background(Color.white.opacity(0.12))
                .cornerRadius(16)
            }
            
            // Other metrics comparison
            if let metrics1 = weather1.metrics, let metrics2 = weather2.metrics {
                VStack(spacing: 10) {
                    if let h1 = metrics1.humidity, let h2 = metrics2.humidity {
                        ComparisonMetricRow(
                            icon: "humidity",
                            label: "Humidity",
                            value1: "\(h1)%",
                            value2: "\(h2)%",
                            delta: h2 - h1,
                            unit: "%",
                            theme: theme
                        )
                    }
                    
                    if let uv1 = metrics1.uvIndex, let uv2 = metrics2.uvIndex {
                        ComparisonMetricRow(
                            icon: "sun.max.fill",
                            label: "UV Index",
                            value1: "\(uv1)",
                            value2: "\(uv2)",
                            delta: uv2 - uv1,
                            unit: "",
                            theme: theme
                        )
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.08))
                .cornerRadius(16)
            }
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
                .foregroundStyle(theme.textColor.opacity(0.4))
            
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
