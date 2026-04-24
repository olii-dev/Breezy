//
//  DailyForecastDetailView.swift
//  Breezy
//
//  Detailed daily forecast view
//

import SwiftUI
import Charts
import Combine
import CoreLocation

struct DailyForecastDetailView: View {
    let day: DailyForecast
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme

    private struct UVSnapshot {
        let hours: [HourlyForecast]
        let peakHour: HourlyForecast?
        let peakValue: Int
        let badge: (String, Color)
        let strongestHours: [HourlyForecast]
        let strongestHoursSummary: String

        var hasData: Bool {
            !hours.isEmpty
        }

        var strongestHourLabel: String? {
            strongestHours.first?.time
        }

        var firstHourLabel: String? {
            hours.first?.time
        }

        var lastHourLabel: String? {
            hours.last?.time
        }

        var spanSummary: String? {
            guard let firstHourLabel, let lastHourLabel else { return nil }
            if firstHourLabel == lastHourLabel {
                return firstHourLabel
            }
            return "\(firstHourLabel) to \(lastHourLabel)"
        }

        var strongestWindowsText: String? {
            strongestHours.count > 1 && !strongestHoursSummary.isEmpty ? strongestHoursSummary : nil
        }
    }

    private struct PrecipitationSnapshot {
        let hours: [HourlyForecast]
        let peakHour: HourlyForecast?
        let peakChancePercent: Int
        let averageChancePercent: Int
        let totalAmount: Double
        let peakAmount: Double
        let clusterHoursSummary: String

        var hasData: Bool {
            !hours.isEmpty
        }

        var isRenderable: Bool {
            hasData && peakHour != nil
        }

        var clusterText: String? {
            hours.count > 1 && !clusterHoursSummary.isEmpty ? clusterHoursSummary : nil
        }
    }

    private struct RainInsightContent {
        let title: String
        let summary: String
        let peakChanceValue: String?
        let totalAmountValue: String?
        let peakAmountValue: String?
        let clusterMessage: String?

        var showsStats: Bool {
            peakChanceValue != nil || totalAmountValue != nil || peakAmountValue != nil
        }
    }

    

    // Interactive scrubbing state
    @State private var selectedHourID: String? = nil
    @State private var dragX: CGFloat? = nil
    @State private var isDragging: Bool = false

    private var resolvedDetailHours: [HourlyForecast] {
        let rawHours: [HourlyForecast]
        if let all = day.allHourlyData, !all.isEmpty {
            rawHours = all
        } else {
            rawHours = day.hourlyData
        }

        let validHours = rawHours
            .filter { $0.temperatureRaw.isFinite }
            .filter { (0...23).contains($0.hourValue) }
            .sorted { lhs, rhs in
                switch (lhs.sourceDate, rhs.sourceDate) {
                case let (leftDate?, rightDate?):
                    if leftDate == rightDate {
                        return lhs.hourValue < rhs.hourValue
                    }
                    return leftDate < rightDate
                default:
                    if lhs.hourValue == rhs.hourValue {
                        return lhs.time < rhs.time
                    }
                    return lhs.hourValue < rhs.hourValue
                }
            }

        var seenIDs = Set<String>()
        return validHours.filter { seenIDs.insert($0.id).inserted }
    }

    private var sanitizedChartHours: [HourlyForecast] {
        var seenHours = Set<Int>()
        return resolvedDetailHours.filter { seenHours.insert($0.hourValue).inserted }
    }

    private func chartAxisStride(for hours: [HourlyForecast]) -> Int {
        switch hours.count {
        case 0...6:
            return 1
        case 7...12:
            return 2
        default:
            return 3
        }
    }

    private func maxUVIndex(in hours: [HourlyForecast]) -> Int? {
        let uvValues = hours.compactMap { $0.uvIndex }
        return uvValues.max()
    }

    private func chartLabelHours(for hours: [HourlyForecast]) -> [Int] {
        let values = hours.map(\.hourValue)
        guard !values.isEmpty else { return [] }

        let stride = chartAxisStride(for: hours)
        return values.enumerated().compactMap { index, hourValue in
            if index == 0 || index == values.count - 1 || index % stride == 0 {
                return hourValue
            }
            return nil
        }
    }

    private func temperatureRange(for hours: [HourlyForecast]) -> ClosedRange<Double> {
        let temperatures = hours.map(\.temperatureRaw)
        guard let minTemperature = temperatures.min(), let maxTemperature = temperatures.max() else {
            return 0...100
        }

        if minTemperature == maxTemperature {
            let padding = max(2, abs(minTemperature) * 0.1)
            return (minTemperature - padding)...(maxTemperature + padding)
        }

        let padding = max(2, (maxTemperature - minTemperature) * 0.15)
        return (minTemperature - padding)...(maxTemperature + padding)
    }

    private func selectedChartHour(in hours: [HourlyForecast]) -> HourlyForecast? {
        guard let selectedHourID else { return nil }
        return hours.first { $0.id == selectedHourID }
    }

    private func precipitationSnapshot(from detailHours: [HourlyForecast]) -> PrecipitationSnapshot {
        let hours = detailHours.filter {
            ($0.precipitationChance ?? 0) > 0.01 || ($0.precipitationAmount ?? 0) > 0.01
        }
        let peakHour = hours.max { lhs, rhs in
            let lhsChance = lhs.precipitationChance ?? 0
            let rhsChance = rhs.precipitationChance ?? 0

            if lhsChance == rhsChance {
                return (lhs.precipitationAmount ?? 0) < (rhs.precipitationAmount ?? 0)
            }

            return lhsChance < rhsChance
        }
        let peakChancePercent = Int((peakHour?.precipitationChance ?? 0) * 100)
        let chances: [Double] = hours.map { $0.precipitationChance ?? 0 }
        let sum = chances.reduce(0.0, +)
        let average = sum / Double(max(hours.count, 1))
        let totalAmount = hours.reduce(0.0) { $0 + ($1.precipitationAmount ?? 0) }
        let peakAmount = hours.map { $0.precipitationAmount ?? 0 }.max() ?? 0
        let clusterHoursSummary = hours.isEmpty ? "" : hours.prefix(3).map(\.time).joined(separator: ", ")

        return PrecipitationSnapshot(
            hours: hours,
            peakHour: peakHour,
            peakChancePercent: peakChancePercent,
            averageChancePercent: Int(average * 100),
            totalAmount: totalAmount,
            peakAmount: peakAmount,
            clusterHoursSummary: clusterHoursSummary
        )
    }

    private func uvSnapshot(from detailHours: [HourlyForecast]) -> UVSnapshot {
        let hours = detailHours.filter { ($0.uvIndex ?? 0) > 0 }
        let rankedHours = hours.sorted { lhs, rhs in
            let leftUV = lhs.uvIndex ?? 0
            let rightUV = rhs.uvIndex ?? 0

            if leftUV != rightUV {
                return leftUV > rightUV
            }

            switch (lhs.sourceDate, rhs.sourceDate) {
            case let (leftDate?, rightDate?):
                if leftDate != rightDate {
                    return leftDate < rightDate
                }
            default:
                break
            }

            if lhs.hourValue != rhs.hourValue {
                return lhs.hourValue < rhs.hourValue
            }

            return lhs.time < rhs.time
        }

        let topHours = Array(rankedHours.prefix(3))
        let peakHour = topHours.first
        let peakValue = peakHour?.uvIndex ?? 0
        let strongestHoursSummary = topHours
            .map { "\($0.time) (\($0.uvIndex ?? 0))" }
            .joined(separator: ", ")

        return UVSnapshot(
            hours: hours,
            peakHour: peakHour,
            peakValue: peakValue,
            badge: uvBadge(for: peakValue),
            strongestHours: topHours,
            strongestHoursSummary: strongestHoursSummary
        )
    }

    private func uvWidgetContent(from snapshot: UVSnapshot) -> UVIndexWidget.Content {
        if !snapshot.hasData {
            return UVIndexWidget.Content(
                uvIndex: nil,
                summary: "Breezy does not have enough hourly UV detail for this day yet."
            )
        }

        if let spanSummary = snapshot.spanSummary {
            var message = "Verified UV coverage runs from \(spanSummary). The highest verified reading reaches \(snapshot.peakValue)."

            if let strongestWindowsText = snapshot.strongestWindowsText {
                message += " Strongest verified hours: \(strongestWindowsText)."
            }

            return UVIndexWidget.Content(
                title: "UV Index",
                uvIndex: snapshot.peakValue,
                category: snapshot.badge.0,
                summary: message
            )
        }

        return UVIndexWidget.Content(
            uvIndex: snapshot.peakValue,
            category: snapshot.badge.0,
            summary: "Breezy found some UV data, but not enough verified hourly detail to summarize the full day yet."
        )
    }

    private func rainInsightContent(from snapshot: PrecipitationSnapshot) -> RainInsightContent {
        guard snapshot.isRenderable, let peakHour = snapshot.peakHour else {
            return RainInsightContent(
                title: "No notable rain signal",
                summary: "No stronger precipitation window or measurable accumulation stands out in the hourly breakdown for this day.",
                peakChanceValue: nil,
                totalAmountValue: nil,
                peakAmountValue: nil,
                clusterMessage: nil
            )
        }

        let totalAmountValue = viewModel.formattedPrecipitationAmount(snapshot.totalAmount)
        let peakAmountValue = viewModel.formattedPrecipitationAmount(snapshot.peakAmount)
        let summary: String

        if snapshot.totalAmount > 0.01 {
            summary = "Rain odds peak near \(snapshot.peakChancePercent)% around \(peakHour.time), with roughly \(totalAmountValue) expected across the day."
        } else {
            summary = "Rain odds peak near \(snapshot.peakChancePercent)% around \(peakHour.time), but measurable accumulation still looks very light."
        }

        return RainInsightContent(
            title: "Best chance is around \(peakHour.time)",
            summary: summary,
            peakChanceValue: "\(snapshot.peakChancePercent)%",
            totalAmountValue: totalAmountValue,
            peakAmountValue: peakAmountValue,
            clusterMessage: snapshot.clusterText.map { "Wettest hours cluster around \($0)." }
        )
    }

    private func resetInteractiveState() {
        selectedHourID = nil
        dragX = nil
        isDragging = false
    }

    var body: some View {
        let detailHours = resolvedDetailHours
        let hourlyChartHours = sanitizedChartHours
        let precipitation = precipitationSnapshot(from: detailHours)
        let rainContent = rainInsightContent(from: precipitation)
        let uv = uvSnapshot(from: detailHours)
        let uvContent = uvWidgetContent(from: uv)
        let dailyMaxUVIndex = maxUVIndex(in: hourlyChartHours)
        let hasQuickStats = day.chanceOfRain != nil || day.windSpeed != nil || dailyMaxUVIndex != nil || day.humidity != nil
        let theme = viewModel.currentTheme(colorScheme: colorScheme)

        ZStack {
            AnimatedGradientBackground(
                colors: [theme.topColor, theme.bottomColor]
            )

            ScrollView {
                dailySections(
                    theme: theme,
                    detailHours: detailHours,
                    hourlyChartHours: hourlyChartHours,
                    rainContent: rainContent,
                    uvContent: uvContent,
                    dailyMaxUVIndex: dailyMaxUVIndex,
                    hasQuickStats: hasQuickStats
                )
            }
        }
        .navigationTitle(day.dayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(viewModel.currentTheme(colorScheme: colorScheme).topColor.opacity(0.8), for: .navigationBar)
        .toolbarColorScheme(viewModel.appearanceMode == .light ? .light : .dark, for: .navigationBar)
        .id(day.id)
        .onChange(of: day.id) { _, _ in
            resetInteractiveState()
        }
        .onChange(of: sanitizedChartHours.map(\.id)) { _, newValues in
            if let selectedHourID, !newValues.contains(selectedHourID) {
                resetInteractiveState()
            }
        }
    }

    @ViewBuilder
    private func dailySections(
        theme: WeatherTheme,
        detailHours: [HourlyForecast],
        hourlyChartHours: [HourlyForecast],
        rainContent: RainInsightContent,
        uvContent: UVIndexWidget.Content,
        dailyMaxUVIndex: Int?,
        hasQuickStats: Bool
    ) -> some View {
        VStack(spacing: DesignSystem.spacingL) {
            heroSection(theme: theme)

            if viewModel.showQuickStatsInDayDetail && hasQuickStats {
                quickStatsSection(theme: theme, maxUVIndex: dailyMaxUVIndex)
                    .padding(.horizontal, DesignSystem.spacingM)
            }

            if viewModel.showHourlyChartsInDayDetail {
                if hourlyChartHours.count >= 2 {
                    chartSection(theme: theme, hours: hourlyChartHours)
                } else {
                    emptyChartPlaceholder(theme: theme)
                }
            }

            if viewModel.showPrecipitationChartInDayDetail {
                precipitationOutlookSection(theme: theme, content: rainContent)
            }

            if viewModel.showUVChartInDayDetail {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(title: "UV Outlook", theme: theme)

                    UVIndexWidget(
                        content: uvContent,
                        viewModel: viewModel,
                        style: "standard",
                        showsCategory: true
                    )
                    .padding(.horizontal, DesignSystem.spacingM)
                }
            }

            if viewModel.showHourlyBreakdownInDayDetail && !detailHours.isEmpty {
                hourlyBreakdownSection(theme: theme, allHours: detailHours)
            }

            if viewModel.showSunMoonInDayDetail {
                sunAndMoonSection(theme: theme)
            }

            if viewModel.showWindChartInDayDetail {
                WindDetailSection(day: day, theme: theme)
            }
        }
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
    // MARK: - Subviews to reduce body complexity
    
    private func heroSection(theme: WeatherTheme) -> some View {
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
        }
        .padding(.top, DesignSystem.spacingXL)
        .padding(.horizontal, DesignSystem.spacingM)
    }
    
    private func quickStatsSection(theme: WeatherTheme, maxUVIndex: Int?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "At a Glance", theme: theme)

            HStack(spacing: DesignSystem.spacingS) {
                if let rain = day.chanceOfRain, !viewModel.showPrecipitationChartInDayDetail {
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
                if let humidity = day.humidity {
                    QuickStatPill(
                        icon: "humidity.fill",
                        emoji: "💧",
                        label: "Humidity",
                        value: humidity,
                        useEmoji: !viewModel.useMinimalistIcons,
                        textColor: theme.textColor
                    )
                }
            }
        }
    }
    private func hourlyBreakdownSection(theme: WeatherTheme, allHours: [HourlyForecast]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "24-Hour Forecast", theme: theme)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.spacingS) {
                    ForEach(Array(allHours.prefix(24).enumerated()), id: \.offset) { _, hour in
                        HourlyDetailCard(
                            hour: hour,
                            viewModel: viewModel,
                            textColor: theme.textColor
                        )
                    }
                }
                .padding(.horizontal, DesignSystem.spacingM)
            }
        }
    }

    private func emptyChartPlaceholder(theme: WeatherTheme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Hourly Temperatures", theme: theme)

            VStack(alignment: .leading, spacing: 8) {
                Text("Hourly forecast unavailable")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(theme.textColor)

                Text("Breezy does not have enough hourly detail for this day yet, so the chart is hidden instead of showing broken data.")
                    .font(.caption)
                    .foregroundColor(theme.textColor.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                    .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                            .stroke(theme.textColor.opacity(0.18), lineWidth: 0.5)
                    )
            )
            .shadow(color: Color.black.opacity(0.15), radius: 18, x: 0, y: 10)
            .padding(.horizontal, 12)
        }
    }

    private func precipitationOutlookSection(theme: WeatherTheme, content: RainInsightContent) -> some View {
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Rain Outlook", theme: theme)

            if !content.showsStats {
                insightPlaceholderCard(
                    title: content.title,
                    message: content.summary,
                    theme: theme
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(content.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(theme.textColor)

                    Text(content.summary)
                        .font(.caption)
                        .foregroundColor(theme.textColor.opacity(0.7))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        if let peakChanceValue = content.peakChanceValue {
                            WeatherStatBlock(title: "Peak Odds", value: peakChanceValue, textColor: theme.textColor)
                        }

                        if let totalAmountValue = content.totalAmountValue {
                            WeatherStatBlock(title: "Total", value: totalAmountValue, textColor: theme.textColor)
                        }

                        if let peakAmountValue = content.peakAmountValue {
                            WeatherStatBlock(title: "Peak Fall", value: peakAmountValue, textColor: theme.textColor)
                        }
                    }

                    if let clusterMessage = content.clusterMessage {
                        Text(clusterMessage)
                            .font(.caption2)
                            .foregroundColor(theme.textColor.opacity(0.64))
                    }
                }
                .padding(16)
                .background(sectionCardBackground(theme: theme))
                .padding(.horizontal, DesignSystem.spacingM)
            }
        }
    }

    private func insightPlaceholderCard(title: String, message: String, theme: WeatherTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(theme.textColor)

            Text(message)
                .font(.caption)
                .foregroundColor(theme.textColor.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(sectionCardBackground(theme: theme))
        .padding(.horizontal, DesignSystem.spacingM)
    }

    private func sectionCardBackground(theme: WeatherTheme) -> some View {
        RoundedRectangle(cornerRadius: DesignSystem.radiusL)
            .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                    .stroke(theme.textColor.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 18, x: 0, y: 10)
    }

    private func sectionHeader(title: String, theme: WeatherTheme) -> some View {
        DayDetailSectionHeader(
            title: title,
            textColor: theme.textColor
        )
        .padding(.horizontal, DesignSystem.spacingM)
    }
    
    private func sunAndMoonSection(theme: WeatherTheme) -> some View {
        VStack(spacing: DesignSystem.spacingL) {
            sectionHeader(title: "Sun & Moon", theme: theme)

            // Sun Path Card
            // Sun Path Card (Show for all days, but only show progress for Today)
            if let sunrise = day.sunriseDate, let sunset = day.sunsetDate {
                VStack(alignment: .leading, spacing: 0) {
                    Label("Sun Path", systemImage: "sun.max.fill")
                        .font(.caption.weight(.bold))
                        .foregroundColor(theme.textColor.opacity(0.6))
                        .padding(.horizontal)
                        .padding(.top, 16)
                    
                    SunPathView(
                        sunrise: sunrise,
                        sunset: sunset,
                        currentTime: day.dayName == "Today" ? Date() : nil,
                        textColor: theme.textColor
                    )
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                    .padding(.horizontal)
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
                .padding(.horizontal, DesignSystem.spacingM)
            }
            
            // Moon Phase Card
            if let phase = day.moonPhase {
                VStack(alignment: .leading, spacing: 0) {
                    Label("Moon Phase", systemImage: "moon.stars.fill")
                        .font(.caption.weight(.bold))
                        .foregroundColor(theme.textColor.opacity(0.6))
                        .padding(.horizontal)
                        .padding(.top, 16)
                        
                    HStack(spacing: 24) {
                        MoonPhaseView2(
                            phase: phase,
                            size: 60,
                            color: theme.textColor
                        )
                        
                        Divider()
                            .frame(height: 60)
                            .background(theme.textColor.opacity(0.2))
                        
                        VStack(alignment: .leading, spacing: 14) {
                            if let rise = day.moonrise {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(theme.textColor.opacity(0.6))
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text("Moonrise").font(.caption2).opacity(0.7)
                                        Text(rise).font(.subheadline.bold())
                                    }
                                }
                            }
                            
                            if let set = day.moonset {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(theme.textColor.opacity(0.6))
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text("Moonset").font(.caption2).opacity(0.7)
                                        Text(set).font(.subheadline.bold())
                                    }
                                }
                            }
                        }
                        .foregroundColor(theme.textColor)
                        
                        Spacer()
                    }
                    .padding(.bottom, 16)
                    .padding(.horizontal)
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
                .padding(.horizontal, DesignSystem.spacingM)
            }
        }
    }

    private func buildHourlyTemperatureChart(theme: WeatherTheme, hours: [HourlyForecast]) -> some View {
        let interpolation: InterpolationMethod = hours.count >= 4 ? .catmullRom : .linear
        let selectedHour = selectedChartHour(in: hours)
        let range = temperatureRange(for: hours)
        let labelHours = chartLabelHours(for: hours)

        return Chart {
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
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                PointMark(
                    x: .value("Hour", hour.hourValue),
                    y: .value("Temperature", hour.temperatureRaw)
                )
                .symbolSize(selectedHourID == hour.id ? 60 : 20)
                .foregroundStyle(Color.white.opacity(selectedHourID == hour.id ? 1.0 : 0.72))
            }

            if let selectedHour {
                RuleMark(x: .value("Selected Hour", selectedHour.hourValue))
                    .foregroundStyle(theme.textColor.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        VStack(spacing: 4) {
                            Text(viewModel.formattedTemperature(selectedHour.temperatureRaw))
                                .font(.caption.weight(.bold))
                                .foregroundColor(theme.textColor)

                            Text(selectedHour.time)
                                .font(.caption2.weight(.medium))
                                .foregroundColor(theme.textColor.opacity(0.72))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.textColor.opacity(0.1), lineWidth: 0.5))
                    }
            }
        }
        .chartXScale(domain: 0...23)
        .chartYScale(domain: range)
        .chartXAxis {
            AxisMarks(values: labelHours) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                    .foregroundStyle(theme.textColor.opacity(0.12))
                AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(theme.textColor.opacity(0.24))
                AxisValueLabel {
                    if let hour = value.as(Int.self), let match = hours.first(where: { $0.hourValue == hour }) {
                        Text(match.time)
                            .font(.system(size: 11, weight: .medium))
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
                    if let temperature = value.as(Double.self) {
                        Text(viewModel.formattedTemperature(temperature))
                            .font(.system(size: 11, weight: .medium))
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
                                isDragging = true
                                guard hours.count >= 2 else { return }
                                guard let plotFrame = proxy.plotFrame else { return }
                                let frame = geometry[plotFrame]
                                guard frame.width > 0 else { return }
                                let locationX = value.location.x - frame.origin.x
                                guard locationX >= 0, locationX <= frame.width else { return }

                                if let hour: Int = proxy.value(atX: locationX) {
                                    let nearestHour = hours.min { abs($0.hourValue - hour) < abs($1.hourValue - hour) }
                                    if nearestHour?.id != selectedHourID {
                                        HapticsManager.shared.impact(style: .light)
                                    }
                                    selectedHourID = nearestHour?.id
                                    dragX = value.location.x
                                }
                            }
                            .onEnded { _ in
                                isDragging = false
                                resetInteractiveState()
                            }
                    )
            }
        }
    }
    
    private func chartGestureOverlay(geometry g: GeometryProxy, hours: [HourlyForecast]) -> some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let localX = value.location.x - 12
                        let width = max(1, g.size.width - 24)
                        let ratio = min(max(localX / width, 0), 1)
                        let idx = Int(round(ratio * CGFloat(max(hours.count - 1, 0))))
                        if hours.indices.contains(idx) {
                            selectedHourID = hours[idx].id
                            dragX = value.location.x
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            resetInteractiveState()
                        }
                    }
            )
    }

    private func chartSection(theme: WeatherTheme, hours: [HourlyForecast]) -> some View {
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Hourly Temperatures", theme: theme)
            .accessibilityAddTraits(.isHeader)
            
            ZStack {
                RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                    .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                            .stroke(theme.textColor.opacity(0.18), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.15), radius: 18, x: 0, y: 10)
                    .frame(height: 220)
                    .padding(.horizontal, 12)
                
                buildHourlyTemperatureChart(theme: theme, hours: hours)
                    .frame(height: 180)
                    .padding(.horizontal, 12)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Hourly temperature chart")
            }
        }
        .padding(.top, 8)
    }
}

struct DayDetailSectionHeader: View {
    let title: String
    let textColor: Color

    var body: some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .foregroundColor(textColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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
    
    private var weatherIcon: some View {
        if viewModel.useMinimalistIcons {
            return AnyView(
                Image(systemName: viewModel.weatherIcon(for: hour.condition ?? "cloud"))
                    .font(.title2)
                    .foregroundColor(textColor)
                    .symbolRenderingMode(.hierarchical)
                    .frame(height: 28)
            )
        } else {
            return AnyView(
                Text(hour.emoji ?? "☁️")
                    .font(.title2)
                    .frame(height: 28)
            )
        }
    }
    
    private var detailsStack: some View {
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

            if let amount = hour.precipitationAmount, amount > 0.05 {
                HStack(spacing: 3) {
                    Image(systemName: "umbrella.fill")
                        .font(.system(size: 9))
                    Text(viewModel.formattedPrecipitationAmount(amount))
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                    .frame(height: 14)
                .foregroundColor(textColor.opacity(0.72))
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(hour.time)
                .font(.caption.weight(.semibold))
                .foregroundColor(textColor.opacity(0.8))
            
            weatherIcon
            
            Text(viewModel.formattedTemperature(hour.temperatureRaw))
                .font(.body.weight(.semibold))
                .foregroundColor(textColor)

            Text(hour.condition ?? "Forecast")
                .font(.caption2)
                .foregroundColor(textColor.opacity(0.68))
                .lineLimit(2)
                .frame(height: 28, alignment: .topLeading)
            
            detailsStack
        }
        .frame(width: 104, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusS)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusS)
                        .stroke(textColor.opacity(0.12), lineWidth: 0.8)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(hour.time): \(viewModel.formattedTemperature(hour.temperatureRaw)), \(hour.condition ?? "Unknown")")
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

struct DetailGridItem: View {
    let icon: String // System Image Name
    let title: String
    let value: String
    let color: Color
    let glassOpacity: Double = 0.35
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color.opacity(0.8))
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundColor(color.opacity(0.7))
                Text(value)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(color)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                .fill(.ultraThinMaterial.opacity(glassOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                .stroke(color.opacity(0.1), lineWidth: 0.5)
        )
    }
}

struct WindDetailSection: View {
    let day: DailyForecast
    let theme: WeatherTheme
    let glassOpacity: Double = 0.35

    private var parsedWindSpeed: Double? {
        guard let speed = day.windSpeed else { return nil }

        let digitOnly = speed
            .components(separatedBy: CharacterSet(charactersIn: "0123456789." ).inverted)
            .joined()

        if let parsed = Double(digitOnly) {
            return parsed
        }

        if let firstComponent = speed.split(separator: " ").first,
           let parsed = Double(firstComponent) {
            return parsed
        }

        return nil
    }
    
    var body: some View {
        if let speed = parsedWindSpeed, let direction = day.windDirection, let cardinal = day.windDirectionCardinal {
            
            VStack(alignment: .leading, spacing: 12) {
                DayDetailSectionHeader(
                    title: "Wind Conditions",
                    textColor: theme.textColor
                )
                .padding(.horizontal, DesignSystem.spacingM)
                
                HStack {
                    Spacer()
                    WindRoseView(
                        speed: speed,
                        direction: cardinal,
                        degree: direction,
                        color: theme.textColor
                    )
                    Spacer()
                }
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                        .fill(.ultraThinMaterial.opacity(glassOpacity))
                        .overlay(RoundedRectangle(cornerRadius: DesignSystem.radiusL).stroke(theme.textColor.opacity(0.18), lineWidth: 0.5))
                )
                .shadow(color: Color.black.opacity(0.15), radius: 18, x: 0, y: 10)
                .padding(.horizontal, DesignSystem.spacingM)
            }
        }
    }
}

