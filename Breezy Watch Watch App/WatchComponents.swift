//
//  WatchComponents.swift
//  Breezy Watch Watch App
//
//  Reusable UI components for the overhauled Watch App
//

import SwiftUI
import Charts

//
//  WatchComponents.swift
//  Breezy Watch Watch App
//
//  Reusable UI components - Breezy Minimalist Style
//

import SwiftUI
import Charts

// MARK: - Metric Pill (Restored)

struct MetricPill: View {
    let icon: String
    let value: String
    let isSystemImage: Bool
    var textColor: Color = .white
    var backgroundColor: Color = Color.white.opacity(0.1)
    
    var body: some View {
        VStack(spacing: 2) {
            if isSystemImage {
                Image(systemName: icon)
                    .font(.caption2)
            } else {
                Text(icon)
                    .font(.caption2)
            }
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundColor(textColor.opacity(0.9))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(backgroundColor)
        .cornerRadius(12)
        .cornerRadius(12)
    }
}

// MARK: - Daily Forecast Row (Vibrant)

struct WatchDailyForecastRow: View {
    let day: WatchDailyForecast
    let rangeLow: Double // Global min for the week
    let rangeHigh: Double // Global max for the week
    let isMinimalist: Bool
    var textColor: Color = .white
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Day Name
            Text(day.dayName)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundColor(textColor.opacity(0.8))
                .frame(width: 45, alignment: .leading)
            
            // Icon
            VStack {
                if isMinimalist {
                    Image(systemName: day.iconName)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 20)) // Slightly larger
                } else {
                    Text(day.emoji)
                        .font(.system(size: 20))
                }
            }
            .frame(width: 24)
            
            // Temperature Bar Chart (Vibrant & Visible)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Subtle track
                    Capsule()
                        .fill(textColor.opacity(0.1))
                        .frame(height: 5)
                    
                    // The Temp Range Bar
                    Capsule()
                        .fill(LinearGradient(
                            gradient: Gradient(colors: getTempColors(low: day.lowValue, high: day.highValue)),
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: calculateBarWidth(totalWidth: geo.size.width), height: 5)
                        .offset(x: calculateBarOffset(totalWidth: geo.size.width))
                        .shadow(color: getTempColors(low: day.lowValue, high: day.highValue).last?.opacity(0.5) ?? .clear, radius: 4, x: 0, y: 0)
                }
            }
            .frame(height: 5)
            .padding(.horizontal, 4)
            
            // High Temp
            Text(day.highTemp)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundColor(textColor)
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.vertical, 12) // Increased tap target size
        .contentShape(Rectangle()) // Ensure entire area is tappable
    }
    
    // Calculation Helpers
    private func calculateBarWidth(totalWidth: CGFloat) -> CGFloat {
        let totalRange = rangeHigh - rangeLow
        guard totalRange > 0 else { return 0 }
        
        let dayRange = max(day.highValue - day.lowValue, 1.0)
        return CGFloat(dayRange / totalRange) * totalWidth
    }
    
    private func calculateBarOffset(totalWidth: CGFloat) -> CGFloat {
        let totalRange = rangeHigh - rangeLow
        guard totalRange > 0 else { return 0 }
        
        let startOffset = day.lowValue - rangeLow
        return CGFloat(startOffset / totalRange) * totalWidth
    }
    
    private func getTempColors(low: Double, high: Double) -> [Color] {
        // Vibrant Palette
        // Logic: Use low temp for start color, high temp for end color
        return [getColor(for: low), getColor(for: high)]
    }
    
    private func getColor(for temp: Double) -> Color {
        // Assumes Celsius roughly or normalized
        // Simplified mapping
        if temp < 5 { return Color.cyan }
        if temp < 15 { return Color.mint }
        if temp < 25 { return Color.yellow }
        if temp < 30 { return Color.orange }
        return Color.red
    }
}

// MARK: - Hourly Forecast Horizontal (New)

struct HourlyForecastHorizontalView: View {
    let hourly: [WatchHourlyForecast]
    let isMinimalist: Bool
    var textColor: Color = .white
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HOURLY")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(textColor.opacity(0.6))
                .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(hourly) { hour in
                        HourlyCard(hour: hour, isMinimalist: isMinimalist, textColor: textColor)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct HourlyCard: View {
    let hour: WatchHourlyForecast
    let isMinimalist: Bool
    var textColor: Color = .white
    
    var body: some View {
        VStack(spacing: 6) {
            Text(hour.time)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            
            if isMinimalist {
                Image(systemName: hour.iconName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 16))
            } else {
                Text(hour.emoji)
                    .font(.system(size: 16))
            }
            
            Text(hour.temperature)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .foregroundColor(textColor)
        .background(textColor.opacity(0.1))
        .cornerRadius(10)
    }
}





struct MetricsPillsWatchView: View {
    let weather: WatchWeatherData
    @EnvironmentObject var viewModel: WatchWeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        let isMinimalist = viewModel.useMinimalistIcons
        let pills = buildPills()
        
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            ForEach(pills, id: \.title) { pill in
                MetricPill(
                    icon: pill.icon,
                    value: pill.value,
                    isSystemImage: isMinimalist,
                    textColor: viewModel.currentTheme(isSystemDark: colorScheme == .dark).textColor,
                    backgroundColor: viewModel.currentTheme(isSystemDark: colorScheme == .dark).textColor.opacity(0.1)
                )
            }
        }
    }
    
    private func buildPills() -> [(icon: String, title: String, value: String)] {
        var pills: [(String, String, String)] = []
        
        for metric in WeatherMetric.allCases {
            guard viewModel.visibleMetrics.contains(metric) else { continue }
            
            switch metric {
            case .wind:
                if let val = weather.windSpeed {
                    pills.append((isMinimalist ? "wind" : metric.emoji, metric.rawValue, val))
                }
            case .humidity:
                if let val = weather.humidity {
                    pills.append((isMinimalist ? "humidity.fill" : metric.emoji, metric.rawValue, "\(val)%"))
                }
            case .uvIndex:
                if let val = weather.uvIndex {
                    pills.append((isMinimalist ? "sun.max.fill" : metric.emoji, metric.rawValue, "UV \(val)"))
                }
            case .rain:
                if let val = weather.rainChance {
                    pills.append((isMinimalist ? "cloud.rain.fill" : metric.emoji, metric.rawValue, val))
                }
            case .visibility:
                if let val = weather.visibility {
                    pills.append((isMinimalist ? "eye.fill" : metric.emoji, metric.rawValue, val))
                }
            case .pressure:
                if let val = weather.pressure {
                    pills.append((isMinimalist ? "gauge" : metric.emoji, metric.rawValue, val))
                }
            case .dewPoint:
                if let val = weather.dewPoint {
                    pills.append((isMinimalist ? "drop.fill" : metric.emoji, metric.rawValue, val))
                }
            case .cloudCover:
                if let val = weather.cloudCover {
                    pills.append((isMinimalist ? "cloud.fill" : metric.emoji, metric.rawValue, val))
                }
            case .feelsLike:
                if let val = weather.feelsLike {
                    pills.append((isMinimalist ? "thermometer" : metric.emoji, metric.rawValue, val))
                }
            case .sunset:
                if let val = weather.sunset {
                    pills.append((isMinimalist ? "sunset.fill" : metric.emoji, metric.rawValue, val))
                }
            }
        }
        
        return pills.prefix(6).map { $0 } // Limit to 6 for space
    }
    
    private var isMinimalist: Bool { viewModel.useMinimalistIcons }
}

struct SunScheduleView: View {
    let sunrise: String
    let sunset: String
    let isMinimalist: Bool
    var textColor: Color = .white
    
    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 4) {
                if isMinimalist {
                    Image(systemName: "sunrise.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.caption2)
                } else {
                    Text("🌅").font(.caption2)
                }
                Text(sunrise)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundColor(textColor)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(textColor.opacity(0.1))
            .cornerRadius(8)
            
            HStack(spacing: 4) {
                if isMinimalist {
                    Image(systemName: "sunset.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.caption2)
                } else {
                    Text("🌇").font(.caption2)
                }
                Text(sunset)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundColor(textColor)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(textColor.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

struct DayDetailView: View {
    let day: WatchDailyForecast
    @EnvironmentObject var viewModel: WatchWeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        let theme = viewModel.theme(for: day.condition, isSystemDark: colorScheme == .dark)
        
        ZStack {
            // Dynamic Background
            LinearGradient(
                gradient: Gradient(colors: [theme.topColor, theme.bottomColor]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Header
                    Text(day.dayName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(theme.textColor)
                        .padding(.top, 8)
                    
                    // Icon + Condition
                    VStack(spacing: 8) {
                        if viewModel.useMinimalistIcons {
                            Image(systemName: day.iconName)
                                .symbolRenderingMode(.multicolor)
                                .font(.system(size: 50))
                        } else {
                            Text(day.emoji)
                                .font(.system(size: 50))
                        }
                        
                        Text(day.condition)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(theme.textColor.opacity(0.9))
                    }
                
                // Temps
                HStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text("High")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(theme.textColor.opacity(0.6))
                        Text(day.highTemp)
                            .font(.system(size: 24, weight: .light))
                            .foregroundColor(theme.textColor)
                    }
                    
                    VStack(spacing: 4) {
                        Text("Low")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(theme.textColor.opacity(0.6))
                        Text(day.lowTemp)
                            .font(.system(size: 24, weight: .light))
                            .foregroundColor(theme.textColor)
                    }
                }
                .padding(.vertical, 8)
                
                // Details Grid (Balanced for 3 items)
                HStack(spacing: 8) {
                    MetricPill(
                        icon: viewModel.useMinimalistIcons ? "umbrella.fill" : "☔️",
                        value: day.precipitationChance,
                        isSystemImage: viewModel.useMinimalistIcons,
                        textColor: theme.textColor,
                        backgroundColor: theme.textColor.opacity(0.1)
                    )
                    MetricPill(
                        icon: viewModel.useMinimalistIcons ? "wind" : "💨",
                        value: day.maxWindSpeed,
                        isSystemImage: viewModel.useMinimalistIcons,
                        textColor: theme.textColor,
                        backgroundColor: theme.textColor.opacity(0.1)
                    )
                    MetricPill(
                        icon: viewModel.useMinimalistIcons ? "sun.max.fill" : "☀️",
                        value: "UV \(day.uvIndex)",
                        isSystemImage: viewModel.useMinimalistIcons,
                        textColor: theme.textColor,
                        backgroundColor: theme.textColor.opacity(0.1)
                    )
                }
                .padding(.horizontal)
                
                // Hourly Forecast (Horizontal)
                if !day.hourlyForecast.isEmpty {
                    HourlyForecastHorizontalView(hourly: day.hourlyForecast, isMinimalist: viewModel.useMinimalistIcons, textColor: theme.textColor)
                        .padding(.top, 16)
                }

                
                // Sun Schedule (Bottom)
                if let rise = day.sunrise, let set = day.sunset {
                    VStack(spacing: 8) {
                        Text("SUN SCHEDULE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(theme.textColor.opacity(0.6))
                        
                        SunScheduleView(sunrise: rise, sunset: set, isMinimalist: viewModel.useMinimalistIcons, textColor: theme.textColor)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
            .padding()
            .focusable()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
}
