import SwiftUI

// MARK: - Metric Pill (Restored)

struct MetricPill: View {
    let icon: String
    let value: String
    let isSystemImage: Bool
    var textColor: Color = .white
    var backgroundColor: Color = Color.white.opacity(0.1)
    /// Optional category tint for the icon (e.g. AQI band color).
    var iconColor: Color? = nil

    var body: some View {
        VStack(spacing: 2) {
            if isSystemImage {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(iconColor ?? textColor.opacity(0.9))
            } else {
                Text(icon)
                    .font(.caption2)
            }
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(textColor.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(backgroundColor)
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

    @Environment(\.accessibilityReduceMotion) private var watchReduceMotion
    @State private var crownValue: Double = 0
    @State private var selectedID: Date?
    @State private var autoHideTask: Task<Void, Never>?

    private var selectedHour: WatchHourlyForecast? {
        guard let selectedID else { return nil }
        return hourly.first { $0.date == selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HOURLY")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(textColor.opacity(0.6))
                .padding(.horizontal)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(hourly) { hour in
                            HourlyCard(
                                hour: hour,
                                isMinimalist: isMinimalist,
                                textColor: textColor,
                                isHighlighted: selectedID == hour.date
                            )
                            .id(hour.date)
                            .scaleEffect(selectedID == hour.date && !watchReduceMotion ? 1.12 : 1)
                        }
                    }
                    .padding(.horizontal)
                }
                // The crown walks the hours; the selected card enlarges and the
                // detail line beneath shows that hour's numbers.
                .digitalCrownRotation(
                    $crownValue,
                    from: 0,
                    through: Double(max(hourly.count - 1, 0)),
                    by: 1,
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
                .focusable()
                .onChange(of: crownValue) { _, newValue in
                    let index = Int(newValue.rounded())
                    guard hourly.indices.contains(index) else { return }
                    selectedID = hourly[index].date
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(hourly[index].date, anchor: .center)
                    }
                    scheduleSelectionHide()
                }
            }

            if let selected = selectedHour {
                HStack(spacing: 6) {
                    Text(selected.condition)
                    if let chance = selected.precipitationChance {
                        Text("· \(chance)")
                    }
                    if let wind = selected.windSpeedText {
                        Text("· \(wind)")
                    }
                }
                .font(.system(size: 10, design: .rounded))
                .foregroundColor(textColor.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal)
                .transition(.opacity)
            }
        }
        .onDisappear {
            autoHideTask?.cancel()
        }
    }

    private func scheduleSelectionHide() {
        autoHideTask?.cancel()
        autoHideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                selectedID = nil
            }
        }
    }
}

struct HourlyCard: View {
    let hour: WatchHourlyForecast
    let isMinimalist: Bool
    var textColor: Color = .white
    var isHighlighted: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            Text(hour.time)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(minWidth: 66)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .foregroundColor(textColor)
        .background(isHighlighted ? Color.cyan.opacity(0.3) : textColor.opacity(0.1))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.cyan.opacity(isHighlighted ? 0.8 : 0), lineWidth: 1)
        )
    }
}





struct MetricsPillsWatchView: View {
    let weather: WatchWeatherData
    @EnvironmentObject var viewModel: WatchWeatherViewModel
    @Environment(\.colorScheme) var colorScheme

    private struct Pill {
        let icon: String
        let title: String
        let value: String
        var iconColorHex: String? = nil
    }

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
                    backgroundColor: viewModel.currentTheme(isSystemDark: colorScheme == .dark).textColor.opacity(0.1),
                    iconColor: pill.iconColorHex.flatMap { Color(hexString: $0) }
                )
            }
        }
    }

    private func buildPills() -> [Pill] {
        var pills: [Pill] = []

        for metric in WeatherMetric.allCases {
            guard viewModel.visibleMetrics.contains(metric) else { continue }

            switch metric {
            case .wind:
                if let val = weather.windSpeed {
                    pills.append(Pill(icon: isMinimalist ? "wind" : metric.emoji, title: metric.rawValue, value: val))
                }
            case .humidity:
                if let val = weather.humidity {
                    pills.append(Pill(icon: isMinimalist ? "humidity.fill" : metric.emoji, title: metric.rawValue, value: "\(val)%"))
                }
            case .uvIndex:
                if let val = weather.uvIndex {
                    pills.append(Pill(icon: isMinimalist ? "sun.max.fill" : metric.emoji, title: metric.rawValue, value: "UV \(val)"))
                }
            case .rain:
                if let val = weather.rainChance {
                    pills.append(Pill(icon: isMinimalist ? "cloud.rain.fill" : metric.emoji, title: metric.rawValue, value: val))
                }
            case .visibility:
                if let val = weather.visibility {
                    pills.append(Pill(icon: isMinimalist ? "eye.fill" : metric.emoji, title: metric.rawValue, value: val))
                }
            case .pressure:
                if let val = weather.pressure {
                    pills.append(Pill(icon: isMinimalist ? "gauge" : metric.emoji, title: metric.rawValue, value: val))
                }
            case .dewPoint:
                if let val = weather.dewPoint {
                    pills.append(Pill(icon: isMinimalist ? "drop.fill" : metric.emoji, title: metric.rawValue, value: val))
                }
            case .cloudCover:
                if let val = weather.cloudCover {
                    pills.append(Pill(icon: isMinimalist ? "cloud.fill" : metric.emoji, title: metric.rawValue, value: val))
                }
            case .feelsLike:
                if let val = weather.feelsLike {
                    pills.append(Pill(icon: isMinimalist ? "thermometer" : metric.emoji, title: metric.rawValue, value: val))
                }
            case .sunset:
                if let val = weather.sunset {
                    pills.append(Pill(icon: isMinimalist ? "sunset.fill" : metric.emoji, title: metric.rawValue, value: val))
                }
            case .airQuality:
                if let val = weather.aqi {
                    let short = weather.aqiCategory == "Unhealthy for Sensitive Groups" ? "Sensitive" : (weather.aqiCategory ?? "")
                    pills.append(Pill(
                        icon: isMinimalist ? "aqi.medium" : metric.emoji,
                        title: metric.rawValue,
                        value: "AQI \(val) · \(short)",
                        iconColorHex: WatchAQIHelper.colorHex(forUSIndex: val)
                    ))
                }
            }
        }

        return Array(pills.prefix(6)) // Limit to 6 for space
    }

    private var isMinimalist: Bool { viewModel.useMinimalistIcons }
}

extension Color {
    /// Hex string ("RRGGBB", 6 digits) → Color.
    init?(hexString: String) {
        var value: UInt64 = 0
        guard hexString.count == 6, Scanner(string: hexString).scanHexInt64(&value) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

struct SunScheduleView: View {
    let sunrise: String
    let sunset: String
    let isMinimalist: Bool
    var textColor: Color = .white
    
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                scheduleTile(title: "Sunrise", value: sunrise, systemIcon: "sunrise.fill", emoji: "🌅")
                scheduleTile(title: "Sunset", value: sunset, systemIcon: "sunset.fill", emoji: "🌇")
            }

            VStack(spacing: 8) {
                scheduleTile(title: "Sunrise", value: sunrise, systemIcon: "sunrise.fill", emoji: "🌅")
                scheduleTile(title: "Sunset", value: sunset, systemIcon: "sunset.fill", emoji: "🌇")
            }
        }
    }

    @ViewBuilder
    private func scheduleTile(title: String, value: String, systemIcon: String, emoji: String) -> some View {
        HStack(spacing: 6) {
            if isMinimalist {
                Image(systemName: systemIcon)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 13))
            } else {
                Text(emoji)
                    .font(.system(size: 13))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundColor(textColor.opacity(0.55))
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundColor(textColor)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(textColor.opacity(0.1))
        .cornerRadius(10)
    }
}

struct DayDetailView: View {
    let day: WatchDailyForecast
    @EnvironmentObject var viewModel: WatchWeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    @AppStorage(WatchAppStorageKey.showDayMetrics, store: UserDefaults(suiteName: WatchAppStorageKey.appGroup)) private var showDayMetrics = true
    @AppStorage(WatchAppStorageKey.showDaySunSchedule, store: UserDefaults(suiteName: WatchAppStorageKey.appGroup)) private var showDaySunSchedule = true
    
    var body: some View {
        let theme = viewModel.theme(for: day.condition, isSystemDark: colorScheme == .dark)
        
        List {
            // Hero Section (Day + Icon + Condition)
            Section {
                VStack(alignment: .center, spacing: 8) {
                    Text(day.dayName)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    if viewModel.useMinimalistIcons {
                        Image(systemName: day.iconName)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 36))
                    } else {
                        Text(day.emoji)
                            .font(.system(size: 36))
                    }
                    
                    Text(day.condition)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .listRowBackground(Color.clear)
            
            // Temperature Section
            Section {
                HStack {
                    Spacer()
                    VStack(alignment: .center, spacing: 4) {
                        Text("HIGH")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(theme.textColor.opacity(0.6))
                        Text(day.highTemp)
                            .font(.system(size: 22, weight: .semibold))
                    }
                    Spacer()
                    VStack(alignment: .center, spacing: 4) {
                        Text("LOW")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(theme.textColor.opacity(0.6))
                        Text(day.lowTemp)
                            .font(.system(size: 22, weight: .semibold))
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .listRowBackground(Color.clear)
            
            // Details Section
            if showDayMetrics {
                Section("DETAILS") {
                    DetailRow(
                        icon: viewModel.useMinimalistIcons ? "umbrella.fill" : "☔️",
                        title: "Precipitation",
                        value: day.precipitationChance,
                        isSystemImage: viewModel.useMinimalistIcons
                    )
                    
                    DetailRow(
                        icon: viewModel.useMinimalistIcons ? "wind" : "💨",
                        title: "Peak Wind",
                        value: day.maxWindSpeed,
                        isSystemImage: viewModel.useMinimalistIcons
                    )
                    
                    DetailRow(
                        icon: viewModel.useMinimalistIcons ? "sun.max.fill" : "☀️",
                        title: "UV Index",
                        value: day.uvIndex,
                        isSystemImage: viewModel.useMinimalistIcons
                    )
                    
                    DetailRow(
                        icon: viewModel.useMinimalistIcons ? "thermometer.medium" : "🌡",
                        title: "Temp Range",
                        value: "\(Int(day.highValue - day.lowValue))°",
                        isSystemImage: viewModel.useMinimalistIcons
                    )
                }
                .listRowBackground(Color.clear)
            }
            
            // Hourly Section
            if !day.hourlyForecast.isEmpty {
                Section("HOURLY") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Spacer()
                            ForEach(day.hourlyForecast) { hour in
                                VStack(spacing: 4) {
                                    Text(hour.time)
                                        .font(.system(size: 9, weight: .medium))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    
                                    if viewModel.useMinimalistIcons {
                                        Image(systemName: hour.iconName)
                                            .symbolRenderingMode(.multicolor)
                                            .font(.system(size: 14))
                                    } else {
                                        Text(hour.emoji)
                                            .font(.system(size: 14))
                                    }
                                    
                                    Text(hour.temperature)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(minWidth: 50)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(height: 90)
                }
                .listRowBackground(Color.clear)
            }
            
            // Sun Schedule Section
            if showDaySunSchedule, let rise = day.sunrise, let set = day.sunset {
                Section("SUN SCHEDULE") {
                    DetailRow(
                        icon: viewModel.useMinimalistIcons ? "sunrise.fill" : "🌅",
                        title: "Sunrise",
                        value: rise,
                        isSystemImage: viewModel.useMinimalistIcons
                    )

                    DetailRow(
                        icon: viewModel.useMinimalistIcons ? "sunset.fill" : "🌇",
                        title: "Sunset",
                        value: set,
                        isSystemImage: viewModel.useMinimalistIcons
                    )
                }
                .listRowBackground(Color.clear)
            }

            // Moon Section
            if let phase = day.moonPhaseName {
                Section("MOON") {
                    HStack(spacing: 10) {
                        Image(systemName: Self.moonSymbol(forIllumination: day.moonIllumination))
                            .font(.title3)
                            .foregroundStyle(.yellow)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(phase)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            if let illumination = day.moonIllumination {
                                Text("\(Int((illumination * 100).rounded()))% illuminated")
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let moonrise = day.moonrise {
                        DetailRow(
                            icon: viewModel.useMinimalistIcons ? "moonrise.fill" : "🌙",
                            title: "Moonrise",
                            value: WatchDateFormatterHelper.formatTime(moonrise),
                            isSystemImage: viewModel.useMinimalistIcons
                        )
                    }
                    if let moonset = day.moonset {
                        DetailRow(
                            icon: viewModel.useMinimalistIcons ? "moonset.fill" : "🌘",
                            title: "Moonset",
                            value: WatchDateFormatterHelper.formatTime(moonset),
                            isSystemImage: viewModel.useMinimalistIcons
                        )
                    }
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [theme.topColor, theme.bottomColor]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Moon symbol approximated by illuminated fraction.
    private static func moonSymbol(forIllumination illumination: Double?) -> String {
        guard let illumination else { return "moonphase.mixed" }
        switch illumination {
        case ..<0.1: return "moonphase.new.mixed"
        case ..<0.35: return "moonphase.waxing.crescent"
        case ..<0.65: return "moonphase.first.quarter"
        case ..<0.9: return "moonphase.waxing.gibbous"
        default: return "moonphase.full.moon"
        }
    }
}

// Simple detail row helper
struct DetailRow: View {
    let icon: String
    let title: String
    let value: String
    let isSystemImage: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Spacer()
            
            if isSystemImage {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18)
            } else {
                Text(icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
            }
            
            VStack(alignment: .center, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .opacity(0.7)
                
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
