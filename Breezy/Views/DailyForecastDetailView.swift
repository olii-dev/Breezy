//
//  DailyForecastDetailView.swift
//  Breezy
//
//  Detailed daily forecast view
//

import SwiftUI
import Charts

struct DailyForecastDetailView: View {
    let day: DailyForecast
    let viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme

    

    // Interactive scrubbing state
    @State private var selectedHourValue: Int? = nil
    @State private var dragX: CGFloat? = nil
    @State private var isDragging: Bool = false

    // Resolve hourly data outside the view builder to avoid using statements inside the body
    private var resolvedChartHours: [HourlyForecast] {
        if let all = day.allHourlyData, !all.isEmpty {
            return all
        }
        return day.hourlyData
    }

    private var chartAxisStride: Int {
        return resolvedChartHours.count > 12 ? 2 : 3
    }
    
    // MARK: - Day-specific metrics from hourly data
    
    private var maxUVIndex: Int? {
        let uvValues = resolvedChartHours.compactMap { $0.uvIndex }
        return uvValues.max()
    }

    var body: some View {
        ZStack {
            let theme = viewModel.currentTheme(colorScheme: colorScheme)
            AnimatedGradientBackground(
                colors: [theme.topColor, theme.bottomColor]
            )

            ScrollView {
                VStack(spacing: DesignSystem.spacingL) {
                    // MARK: - Hero Section
                    VStack(spacing: DesignSystem.spacingM) {
                        // Large icon
                        if viewModel.useMinimalistIcons {
                            AnimatedWeatherIcon(
                                systemName: viewModel.weatherIcon(for: day.condition),
                                size: 100,
                                condition: day.condition
                            )
                            .padding(.bottom, DesignSystem.spacingXS)
                        } else {
                            Text(day.emoji)
                                .font(.system(size: 80))
                                .padding(.bottom, DesignSystem.spacingXS)
                        }
                        
                        // Condition
                        Text(day.condition)
                            .font(.title2.weight(.medium))
                            .foregroundColor(theme.textColor)
                        
                        // Temperature range
                        HStack(spacing: DesignSystem.spacingM) {
                            VStack(spacing: 4) {
                                Text("High")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(theme.textColor.opacity(0.7))
                                Text(day.highTemp)
                                    .font(.title.weight(.bold))
                                    .foregroundColor(theme.textColor)
                            }
                            
                            Rectangle()
                                .fill(theme.textColor.opacity(0.3))
                                .frame(width: 1, height: 40)
                            
                            VStack(spacing: 4) {
                                Text("Low")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(theme.textColor.opacity(0.7))
                                Text(day.lowTemp)
                                    .font(.title.weight(.semibold))
                                    .foregroundColor(theme.textColor.opacity(0.9))
                            }
                        }
                        
                        // Quick Stats - Rain, Wind, UV Index
                        HStack(spacing: DesignSystem.spacingS) {
                            if let rain = day.chanceOfRain {
                                QuickStatPill(
                                    icon: "cloud.rain.fill",
                                    emoji: "🌧️",
                                    label: "Rain",
                                    value: rain,
                                    useEmoji: !viewModel.useMinimalistIcons,
                                    textColor: theme.textColor
                                )
                            }
                            if let wind = day.windSpeed {
                                QuickStatPill(
                                    icon: "wind",
                                    emoji: "💨",
                                    label: "Wind",
                                    value: wind,
                                    useEmoji: !viewModel.useMinimalistIcons,
                                    textColor: theme.textColor
                                )
                            }
                            if let uv = maxUVIndex {
                                QuickStatPill(
                                    icon: "sun.max.fill",
                                    emoji: "☀️",
                                    label: "UV Index",
                                    value: "\(uv)",
                                    useEmoji: !viewModel.useMinimalistIcons,
                                    textColor: theme.textColor
                                )
                            }
                        }
                        .padding(.horizontal, DesignSystem.spacingL)
                    }
                    .padding(.top, DesignSystem.spacingXL)
                    .padding(.horizontal, DesignSystem.spacingM)
                    
                    // Hourly Forecast Chart — uses resolvedChartHours computed property
                    if !resolvedChartHours.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Hourly Temperatures")
                                .font(.title3.weight(.semibold))
                                .foregroundColor(theme.textColor)
                                .padding(.horizontal)
                                .accessibilityAddTraits(.isHeader)
                            
                            ZStack {
                                RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                                    .fill(.ultraThinMaterial.opacity(0.35))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                                            .stroke(theme.textColor.opacity(0.18), lineWidth: 0.5)
                                    )
                                    .shadow(color: Color.black.opacity(0.15), radius: 18, x: 0, y: 10)
                                    .frame(height: 200)
                                    .padding(.horizontal, 12)
                                
                                let nowHour = Calendar.current.component(.hour, from: Date())

                                Chart(resolvedChartHours) { (hour: HourlyForecast) in
                                    // Subtle area fill
                                    AreaMark(
                                        x: .value("Time", hour.hourValue),
                                        y: .value("Temperature", hour.temperatureRaw)
                                    )
                                    .interpolationMethod(.catmullRom)
                                    .foregroundStyle(
                                        LinearGradient(
                                            gradient: Gradient(colors: [theme.textColor.opacity(0.15), Color.clear]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    
                                    // Main temperature line
                                    LineMark(
                                        x: .value("Time", hour.hourValue),
                                        y: .value("Temperature", hour.temperatureRaw)
                                    )
                                    .interpolationMethod(.catmullRom)
                                    .foregroundStyle(theme.textColor)
                                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                                    
                                    // No inline temperature labels here — show hours along the bottom instead

                                    // Show a visible dot for selected hour; show 'Now' dot only when this view is for today
                                    if hour.hourValue == selectedHourValue || (day.dayName == "Today" && hour.hourValue == nowHour) {
                                        PointMark(
                                            x: .value("Time", hour.hourValue),
                                            y: .value("Temperature", hour.temperatureRaw)
                                        )
                                        .symbolSize(hour.hourValue == selectedHourValue ? 100 : 60)
                                        .foregroundStyle(hour.hourValue == selectedHourValue ? Color.yellow : theme.textColor)
                                    }

                                    // Yellow vertical 'Now' marker — only show for the actual today
                                    if day.dayName == "Today" {
                                        RuleMark(x: .value("Now", nowHour))
                                            .foregroundStyle(Color.yellow.opacity(0.9))
                                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4,6]))
                                            .annotation(position: .top, alignment: .center) {
                                                        // Show 'Now' label plus the current temperature again (user request)
                                                        if let current = resolvedChartHours.first(where: { $0.hourValue == nowHour }) {
                                                            VStack(spacing: 2) {
                                                                Text("Now")
                                                                    .font(.caption2.weight(.semibold))
                                                                    .foregroundColor(.yellow)
                                                                Text(viewModel.formattedTemperature(current.temperatureRaw))
                                                                    .font(.caption2)
                                                                    .foregroundColor(.yellow)
                                                            }
                                                        } else if let currentTempStr = viewModel.weather?.temperature {
                                                            VStack(spacing: 2) {
                                                                Text("Now")
                                                                    .font(.caption2.weight(.semibold))
                                                                    .foregroundColor(.yellow)
                                                                Text(currentTempStr)
                                                                    .font(.caption2)
                                                                    .foregroundColor(.yellow)
                                                            }
                                                        }
                                            }
                                    }
                                }
                                .chartXAxis {
                                    // Force ticks every 3 hours (12 AM, 3 AM, 6 AM, ...) so labels are predictable and evenly spaced
                                    AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                                        AxisValueLabel {
                                            if let hourInt = value.as(Int.self), hourInt >= 0 && hourInt < 24 {
                                                let hourLabel = hourInt == 0 ? "12 AM" : hourInt < 12 ? "\(hourInt) AM" : hourInt == 12 ? "12 PM" : "\(hourInt - 12) PM"
                                                Text(hourLabel)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(theme.textColor.opacity(0.7))
                                            }
                                        }
                                    }
                                }
                                .chartYAxis(.hidden)
                                // Match the rounded rectangle height so axis labels render inside the card
                                .frame(height: 200)
                                .padding(.horizontal, 12)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Hourly temperature chart")

                                // Overlay for handling drag gestures and displaying tooltip
                                .overlay {
                                    GeometryReader { g in
                                        // Clear rectangle to capture gestures
                                        Rectangle()
                                            .fill(Color.clear)
                                            .contentShape(Rectangle())
                                            .gesture(
                                                DragGesture(minimumDistance: 0)
                                                                .onChanged { value in
                                                                    isDragging = true
                                                                    let localX = value.location.x - 12 // account for chart horizontal padding
                                                                    let width = max(1, g.size.width - 24) // subtract padding both sides
                                                                    let ratio = min(max(localX / width, 0), 1)
                                                                    let idx = Int(round(ratio * CGFloat(max(resolvedChartHours.count - 1, 0))))
                                                                    if resolvedChartHours.indices.contains(idx) {
                                                                        selectedHourValue = resolvedChartHours[idx].hourValue
                                                                        dragX = value.location.x
                                                                    }
                                                                }
                                                    .onEnded { _ in
                                                        isDragging = false
                                                        // clear selection when user stops dragging
                                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                            selectedHourValue = nil
                                                            dragX = nil
                                                        }
                                                    }
                                            )
                                            .overlay(alignment: .topLeading) {
                                                // Tooltip
                                                    if let x = dragX, let selVal = selectedHourValue, let selected = resolvedChartHours.first(where: { $0.hourValue == selVal }) {
                                                    VStack(alignment: .leading, spacing: 6) {
                                                        Text(selected.time)
                                                            .font(.caption2.weight(.semibold))
                                                            .foregroundColor(theme.textColor)
                                                        Text(viewModel.formattedTemperature(selected.temperatureRaw, decimals: 1))
                                                            .font(.headline)
                                                            .foregroundColor(theme.textColor)
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
                                                        .foregroundColor(theme.textColor.opacity(0.85))
                                                    }
                                                    .padding(8)
                                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.textColor.opacity(0.12), lineWidth: 0.5))
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
                    
                    // Enhanced Hourly Breakdown
                    if let allHours = day.allHourlyData, !allHours.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Hourly Breakdown")
                                .font(.title3.weight(.semibold))
                                .foregroundColor(theme.textColor)
                                .padding(.horizontal)
                                .accessibilityAddTraits(.isHeader)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(allHours.prefix(24)) { hour in
                                        HourlyDetailCard(hour: hour, viewModel: viewModel, textColor: theme.textColor)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.top, 8)
                    }
                    
                    // Sun & Moon Times with Golden Hour
                    if let sunrise = day.sunrise, let sunset = day.sunset {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Sun & Moon")
                                .font(.title3.weight(.semibold))
                                .foregroundColor(theme.textColor)
                                .padding(.horizontal)
                                .accessibilityAddTraits(.isHeader)
                            
                            VStack(spacing: 12) {
                                // Sunrise/Sunset with Golden Hour
                                HStack(spacing: 16) {
                                    SunTimeCard(
                                        icon: "sunrise.fill",
                                        emoji: "🌅",
                                        time: sunrise,
                                        label: "Sunrise",
                                        isGoldenHour: isGoldenHour(sunriseDate: day.sunriseDate, isMorning: true),
                                        useEmoji: !viewModel.useMinimalistIcons,
                                        textColor: theme.textColor
                                    )
                                    
                                    SunTimeCard(
                                        icon: "sunset.fill",
                                        emoji: "🌇",
                                        time: sunset,
                                        label: "Sunset",
                                        isGoldenHour: isGoldenHour(sunriseDate: day.sunsetDate, isMorning: false),
                                        useEmoji: !viewModel.useMinimalistIcons,
                                        textColor: theme.textColor
                                    )
                                }
                                
                                // Moon Phase & Times
                                if let moonPhase = day.moonPhase {
                                    MoonPhaseCard(
                                        moonPhase: moonPhase,
                                        moonrise: day.moonrise,
                                        moonset: day.moonset,
                                        useEmoji: !viewModel.useMinimalistIcons,
                                        textColor: theme.textColor
                                    )
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                                    .fill(.ultraThinMaterial.opacity(0.35))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                                            .stroke(theme.textColor.opacity(0.18), lineWidth: 0.5)
                                    )
                            )
                            .shadow(color: Color.black.opacity(0.15), radius: 18, x: 0, y: 10)
                            .padding(.horizontal)
                        }
                        .padding(.top, 8)
                    }
                }
            }
        }
        .navigationTitle(day.dayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(viewModel.currentTheme(colorScheme: colorScheme).topColor.opacity(0.8), for: .navigationBar)
        .toolbarColorScheme(viewModel.appearanceMode == .light ? .light : .dark, for: .navigationBar)
    }
    
    private func isGoldenHour(sunriseDate: Date?, isMorning: Bool) -> Bool {
        guard let sunDate = sunriseDate else { return false }
        let now = Date()
        let calendar = Calendar.current
        
        if isMorning {
            // Golden hour is 1 hour before sunrise to 30 minutes after
            let goldenStart = calendar.date(byAdding: .hour, value: -1, to: sunDate) ?? sunDate
            let goldenEnd = calendar.date(byAdding: .minute, value: 30, to: sunDate) ?? sunDate
            return now >= goldenStart && now <= goldenEnd
        } else {
            // Golden hour is 30 minutes before sunset to 1 hour after
            let goldenStart = calendar.date(byAdding: .minute, value: -30, to: sunDate) ?? sunDate
            let goldenEnd = calendar.date(byAdding: .hour, value: 1, to: sunDate) ?? sunDate
            return now >= goldenStart && now <= goldenEnd
        }
    }
    
    private func uvBadge(for uv: Int) -> (String, Color) {
        switch uv {
        case 0...2:
            return ("Low", .green)
        case 3...5:
            return ("Moderate", .yellow)
        case 6...7:
            return ("High", .orange)
        case 8...10:
            return ("Very High", .red)
        default:
            return ("Extreme", .purple)
        }
    }
}

// MARK: - Day Metric Row

struct DayMetricRow: View {
    let icon: String
    let emoji: String
    let label: String
    let value: String
    let badge: (String, Color)?
    let useEmoji: Bool
    let textColor: Color
    
    var body: some View {
        HStack(spacing: DesignSystem.spacingM) {
            // Icon
            if useEmoji {
                Text(emoji)
                    .font(.title2)
                    .frame(width: 36)
            } else {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(textColor.opacity(0.9))
                    .frame(width: 36)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(textColor.opacity(0.8))
                
                if let (badgeText, badgeColor) = badge {
                    Text(badgeText)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(badgeColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(badgeColor.opacity(0.2))
                        .cornerRadius(6)
                }
            }
            
            Spacer()
            
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundColor(textColor)
        }
    }
}

struct HourlyDetailCard: View {
    let hour: HourlyForecast
    let viewModel: WeatherViewModel
    let textColor: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(hour.time)
                .font(.caption.weight(.semibold))
                .foregroundColor(textColor.opacity(0.8))
            
            // Icon (emoji or symbol)
            if viewModel.useMinimalistIcons {
                Image(systemName: viewModel.weatherIcon(for: hour.condition))
                    .font(.title2)
                    .foregroundColor(textColor)
                    .symbolRenderingMode(.hierarchical)
                    .frame(height: 28)
            } else {
                Text(hour.emoji)
                    .font(.title2)
                    .frame(height: 28)
            }
            
            Text(viewModel.formattedTemperature(hour.temperatureRaw))
                .font(.body.weight(.semibold))
                .foregroundColor(textColor)
            
            VStack(spacing: 4) {
                if let rain = hour.precipitationChance, rain > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 9))
                        Text("\(Int(rain * 100))%")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(textColor.opacity(0.75))
                }
                
                if let wind = hour.windSpeed {
                    HStack(spacing: 3) {
                        Image(systemName: "wind")
                            .font(.system(size: 9))
                        Text(wind)
                            .font(.system(size: 10))
                    }
                    .foregroundColor(textColor.opacity(0.7))
                }
            }
        }
        .frame(width: 85)
        .padding(.vertical, DesignSystem.spacingM)
        .softGlassCard(padding: DesignSystem.spacingS, cornerRadius: DesignSystem.radiusS)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(hour.time): \(viewModel.formattedTemperature(hour.temperatureRaw)), \(hour.condition)")
    }
}

struct SunTimeCard: View {
    let icon: String
    let emoji: String
    let time: String
    let label: String
    let isGoldenHour: Bool
    let useEmoji: Bool
    let textColor: Color
    
    var body: some View {
        VStack(spacing: 8) {
            if useEmoji {
                Text(emoji)
                    .font(.title2)
            } else {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isGoldenHour ? .yellow : textColor.opacity(0.8))
            }
            
            Text(label)
                .font(.caption)
                .foregroundColor(textColor.opacity(0.7))
            
            Text(time)
                .font(.headline)
                .foregroundColor(textColor)
            
            if isGoldenHour {
                Text("Golden Hour")
                    .font(.caption2)
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.yellow.opacity(0.2))
                    .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(textColor.opacity(0.1))
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(time)\(isGoldenHour ? ", currently golden hour" : "")")
    }
}

struct MoonPhaseCard: View {
    let moonPhase: MoonPhase
    let moonrise: String?
    let moonset: String?
    let useEmoji: Bool
    let textColor: Color
    
    var body: some View {
        HStack(spacing: 16) {
            if useEmoji {
                Text(MoonPhaseHelper.emoji(for: moonPhase.phase))
                    .font(.title2)
                    .frame(width: 32)
            } else {
                Image(systemName: moonPhase.icon)
                    .font(.title2)
                    .foregroundColor(textColor.opacity(0.8))
                    .frame(width: 32)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(moonPhase.phase)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(textColor)
                
                Text("\(Int(moonPhase.illumination * 100))% illuminated")
                    .font(.caption2)
                    .foregroundColor(textColor.opacity(0.6))
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                if let rise = moonrise {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .font(.caption2)
                        Text(rise)
                            .font(.caption2)
                    }
                    .foregroundColor(textColor.opacity(0.7))
                }
                
                if let set = moonset {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .font(.caption2)
                        Text(set)
                            .font(.caption2)
                    }
                    .foregroundColor(textColor.opacity(0.7))
                }
            }
        }
        .padding()
        .background(textColor.opacity(0.1))
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Moon phase: \(moonPhase.phase), \(Int(moonPhase.illumination * 100))% illuminated")
    }
}

// MARK: - Metric Row (Replaces DetailRow with pastel aesthetic)

struct MetricRow: View {
    let icon: String
    let emoji: String
    let title: String
    let value: String
    let useEmoji: Bool
    let textColor: Color
    
    var body: some View {
        HStack(spacing: DesignSystem.spacingS) {
            // Icon or Emoji
            if useEmoji {
                Text(emoji)
                    .font(.title3)
                    .frame(width: 32)
            } else {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(textColor.opacity(0.9))
                    .frame(width: 32)
            }
            
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(textColor.opacity(0.8))
            
            Spacer()
            
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(textColor)
        }
        .padding(.vertical, DesignSystem.spacingXS)
    }
}

struct DetailRow: View {
    let icon: String
    let title: String
    let value: String
    let textColor: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(textColor.opacity(0.8))
                .frame(width: 30)
            Text(title)
                .font(.subheadline)
                .foregroundColor(textColor.opacity(0.7))
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(textColor)
        }
        .padding(.vertical, 4)
    }
}
