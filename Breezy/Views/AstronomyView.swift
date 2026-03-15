//
//  AstronomyView.swift
//  Breezy
//
//  Astronomy detail surfaces
//

import SwiftUI

struct AstronomyDetailView: View {
    let weather: WeatherInfo
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedDayIndex = 0

    private struct SolarSummary {
        let sunrise: Date?
        let sunset: Date?
        let sunriseText: String?
        let sunsetText: String?
        let daylightDuration: String?
        let daylightStatus: String
        let goldenHourMorning: String?
        let goldenHourEvening: String?
    }

    private struct LunarSummary {
        let phase: MoonPhase
        let illuminationText: String
        let primaryStatus: String
        let eventSummary: String
        let visibilitySummary: String
        let moonrise: String?
        let moonset: String?
    }

    private var theme: WeatherTheme {
        viewModel.currentTheme(colorScheme: colorScheme)
    }

    private var selectedForecast: DailyForecast? {
        guard weather.dailyForecast.indices.contains(selectedDayIndex) else {
            return weather.dailyForecast.first
        }

        return weather.dailyForecast[selectedDayIndex]
    }

    private var solarSummary: SolarSummary? {
        guard let selectedForecast else { return nil }

        let sunrise = selectedForecast.sunriseDate
        let sunset = selectedForecast.sunsetDate
        let sunriseText = selectedForecast.sunrise
        let sunsetText = selectedForecast.sunset

        let daylightDuration: String?
        if let sunrise, let sunset {
            daylightDuration = formattedDuration(from: sunrise, to: sunset)
        } else {
            daylightDuration = nil
        }

        let goldenHourMorning = formattedGoldenHourWindow(around: sunrise, leadingMinutes: 30, trailingMinutes: 60)
        let goldenHourEvening = formattedGoldenHourWindow(around: sunset, leadingMinutes: 60, trailingMinutes: 30)

        return SolarSummary(
            sunrise: sunrise,
            sunset: sunset,
            sunriseText: sunriseText,
            sunsetText: sunsetText,
            daylightDuration: daylightDuration,
            daylightStatus: daylightStatus(sunrise: sunrise, sunset: sunset),
            goldenHourMorning: goldenHourMorning,
            goldenHourEvening: goldenHourEvening
        )
    }

    private var lunarSummary: LunarSummary? {
        guard let selectedForecast, let phase = selectedForecast.moonPhase else { return nil }

        return LunarSummary(
            phase: phase,
            illuminationText: "\(Int((phase.illumination * 100).rounded()))% illuminated",
            primaryStatus: moonPrimaryStatus(for: phase),
            eventSummary: moonEventSummary(moonrise: selectedForecast.moonrise, moonset: selectedForecast.moonset),
            visibilitySummary: moonVisibilitySummary(for: phase),
            moonrise: selectedForecast.moonrise,
            moonset: selectedForecast.moonset
        )
    }

    private var selectedDayName: String {
        selectedForecast?.dayName ?? "Today"
    }

    private var isViewingToday: Bool {
        selectedDayName == "Today"
    }

    var body: some View {
        ZStack {
            AnimatedGradientBackground(colors: [theme.topColor, theme.bottomColor])

            ScrollView {
                VStack(spacing: DesignSystem.spacingL) {
                    astronomyHero

                    if weather.dailyForecast.count > 1 {
                        forecastPickerCard
                    }

                    if let solarSummary, let lunarSummary {
                        astronomySnapshotCard(solar: solarSummary, lunar: lunarSummary)
                    } else if let solarSummary {
                        astronomySnapshotCard(solar: solarSummary, lunar: nil)
                    } else if let lunarSummary {
                        astronomySnapshotCard(solar: nil, lunar: lunarSummary)
                    }

                    if let solarSummary {
                        sunOverviewCard(summary: solarSummary)

                        if let sunrise = solarSummary.sunrise, let sunset = solarSummary.sunset {
                            sunPathCard(sunrise: sunrise, sunset: sunset)
                        }
                    }

                    if let lunarSummary {
                        moonOverviewCard(summary: lunarSummary)
                    }

                    if solarSummary == nil && lunarSummary == nil {
                        placeholderCard(
                            title: "Astronomy data unavailable",
                            message: "Breezy does not have enough sunrise, sunset, or moon data for this location yet."
                        )
                    }
                }
                .padding(.horizontal, DesignSystem.spacingM)
                .padding(.top, DesignSystem.spacingL)
                .padding(.bottom, DesignSystem.spacingXL)
            }
        }
        .navigationTitle("Astronomy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(theme.topColor.opacity(0.82), for: .navigationBar)
        .toolbarColorScheme(theme.isDark ? .dark : .light, for: .navigationBar)
        .onChange(of: weather.dailyForecast.count) { _, _ in clampSelectedDayIndex() }
    }

    private var astronomyHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(weather.location.city)
                .font(.title2.weight(.bold))
                .foregroundColor(theme.textColor)

            Text(heroSubtitle)
                .font(.subheadline)
                .foregroundColor(theme.textColor.opacity(0.74))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(cardBackground)
    }

    private var heroSubtitle: String {
        if let selectedForecast {
            return "Sun and moon timing for \(selectedForecast.dayName.lowercased())."
        }
        return "Sun and moon timing built from the current forecast."
    }

    private var forecastPickerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Forecast Window")
                .font(.caption.weight(.bold))
                .foregroundColor(theme.textColor.opacity(0.6))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(weather.dailyForecast.enumerated()), id: \.offset) { index, forecast in
                        Button {
                            HapticsManager.shared.selectionChanged()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedDayIndex = index
                            }
                        } label: {
                            forecastChip(index: index, forecast: forecast)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(cardBackground)
    }

    private func forecastChip(index: Int, forecast: DailyForecast) -> some View {
        let isSelected = index == selectedDayIndex
        let chipFill = isSelected ? theme.textColor.opacity(0.18) : Color.white.opacity(0.08)
        let chipStroke = theme.textColor.opacity(isSelected ? 0.28 : 0.12)
        let secondaryText = theme.textColor.opacity(isSelected ? 0.82 : 0.6)

        return VStack(alignment: .leading, spacing: 4) {
            Text(forecast.dayName)
                .font(.subheadline.weight(.semibold))

            Text(forecast.date)
                .font(.caption)
                .foregroundColor(secondaryText)
        }
        .foregroundColor(theme.textColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                .fill(chipFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                .stroke(chipStroke, lineWidth: 0.75)
        )
    }

    private func astronomySnapshotCard(solar: SolarSummary?, lunar: LunarSummary?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Astronomy Snapshot", systemImage: "sparkles")
                .font(.headline.weight(.semibold))
                .foregroundColor(theme.textColor)

            HStack(spacing: 12) {
                if let solar {
                    overviewTile(
                        title: isViewingToday ? "Today" : selectedDayName,
                        value: solar.daylightStatus,
                        detail: solar.daylightDuration.map { "Daylight \($0)" } ?? "Sun timing unavailable"
                    )
                }

                if let lunar {
                    overviewTile(
                        title: "Moon",
                        value: lunar.primaryStatus,
                        detail: lunar.illuminationText
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(cardBackground)
    }

    private func overviewTile(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(theme.textColor.opacity(0.62))

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(theme.textColor)
                .fixedSize(horizontal: false, vertical: true)

            Text(detail)
                .font(.caption)
                .foregroundColor(theme.textColor.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusS)
                .fill(Color.white.opacity(0.08))
        )
    }

    private func sunOverviewCard(summary: SolarSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Label("Sun", systemImage: "sun.max.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(theme.textColor)

                Spacer()

                Text(summary.daylightStatus)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(theme.textColor.opacity(0.74))
                    .multilineTextAlignment(.trailing)
            }

            HStack(spacing: 12) {
                AstronomyStatTile(title: "Sunrise", value: summary.sunriseText ?? "—", textColor: theme.textColor)
                AstronomyStatTile(title: "Sunset", value: summary.sunsetText ?? "—", textColor: theme.textColor)
                AstronomyStatTile(title: "Daylight", value: summary.daylightDuration ?? "—", textColor: theme.textColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                if let goldenHourMorning = summary.goldenHourMorning {
                    Text("Morning golden hour: \(goldenHourMorning)")
                        .font(.caption)
                        .foregroundColor(theme.textColor.opacity(0.72))
                }

                if let goldenHourEvening = summary.goldenHourEvening {
                    Text("Evening golden hour: \(goldenHourEvening)")
                        .font(.caption)
                        .foregroundColor(theme.textColor.opacity(0.72))
                }
            }

            if let solarNote = solarPlanningNote(summary: summary) {
                Text(solarNote)
                    .font(.caption)
                    .foregroundColor(theme.textColor.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(cardBackground)
    }

    private func sunPathCard(sunrise: Date, sunset: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Sun Path", systemImage: "sun.and.horizon.fill")
                .font(.caption.weight(.bold))
                .foregroundColor(theme.textColor.opacity(0.6))
                .padding(.horizontal)
                .padding(.top, 16)

            SunPathView(
                sunrise: sunrise,
                sunset: sunset,
                currentTime: isViewingToday ? Date() : nil,
                textColor: theme.textColor,
                style: "full",
                showsCountdown: isViewingToday
            )
            .padding(.top, 16)
            .padding(.bottom, 16)
            .padding(.horizontal)
        }
        .background(cardBackground)
    }

    private func moonOverviewCard(summary: LunarSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Label("Moon", systemImage: "moon.stars.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(theme.textColor)

                Spacer()

                Text(summary.primaryStatus)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(theme.textColor.opacity(0.74))
            }

            HStack(spacing: 24) {
                MoonPhaseView2(
                    phase: summary.phase,
                    size: 92,
                    color: theme.textColor
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.phase.phase)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(theme.textColor)

                    Text(summary.illuminationText)
                        .font(.subheadline)
                        .foregroundColor(theme.textColor.opacity(0.72))

                    Text(summary.visibilitySummary)
                        .font(.caption)
                        .foregroundColor(theme.textColor.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            HStack(spacing: 12) {
                AstronomyStatTile(title: "Moonrise", value: summary.moonrise ?? "—", textColor: theme.textColor)
                AstronomyStatTile(title: "Moonset", value: summary.moonset ?? "—", textColor: theme.textColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(summary.eventSummary)
                    .font(.caption)
                    .foregroundColor(theme.textColor.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)

                Text(summary.visibilitySummary)
                    .font(.caption)
                    .foregroundColor(theme.textColor.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(cardBackground)
    }

    private func solarPlanningNote(summary: SolarSummary) -> String? {
        if let goldenHourMorning = summary.goldenHourMorning, let goldenHourEvening = summary.goldenHourEvening {
            return "Best light runs from \(goldenHourMorning) in the morning and \(goldenHourEvening) toward sunset."
        }

        if let goldenHourMorning = summary.goldenHourMorning {
            return "The best early light window is \(goldenHourMorning)."
        }

        if let goldenHourEvening = summary.goldenHourEvening {
            return "The best late light window is \(goldenHourEvening)."
        }

        return nil
    }

    private func placeholderCard(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundColor(theme.textColor)

            Text(message)
                .font(.caption)
                .foregroundColor(theme.textColor.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: DesignSystem.radiusL)
            .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                    .stroke(theme.textColor.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 18, x: 0, y: 10)
    }

    private func daylightStatus(sunrise: Date?, sunset: Date?) -> String {
        guard let sunrise, let sunset else { return "Sun timing unavailable" }

        let now = Date()
        if now < sunrise {
            return "Sunrise in \(relativeDuration(from: now, to: sunrise))"
        }

        if now < sunset {
            return "Sunset in \(relativeDuration(from: now, to: sunset))"
        }

        return "Sunset has already passed"
    }

    private func formattedDuration(from start: Date, to end: Date) -> String {
        let interval = max(0, end.timeIntervalSince(start))
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    private func relativeDuration(from start: Date, to end: Date) -> String {
        let interval = max(0, end.timeIntervalSince(start))
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }

    private func formattedGoldenHourWindow(around date: Date?, leadingMinutes: Int, trailingMinutes: Int) -> String? {
        guard let date else { return nil }
        let start = Calendar.current.date(byAdding: .minute, value: -leadingMinutes, to: date)
        let end = Calendar.current.date(byAdding: .minute, value: trailingMinutes, to: date)
        guard let start, let end else { return nil }
        return "\(DateFormatterHelper.formatTime(start)) to \(DateFormatterHelper.formatTime(end))"
    }

    private func moonEventSummary(moonrise: String?, moonset: String?) -> String {
        switch (moonrise, moonset) {
        case let (rise?, set?):
            return "The moon rises at \(rise) and sets at \(set), so you can judge whether it will still be out after sunset."
        case let (rise?, nil):
            return "Moonrise is expected at \(rise). Breezy does not have a verified moonset time for this day."
        case let (nil, set?):
            return "Moonset is expected at \(set). Breezy does not have a verified moonrise time for this day."
        default:
            return "Breezy does not have verified moonrise or moonset timing for this day."
        }
    }

    private func moonVisibilitySummary(for phase: MoonPhase) -> String {
        switch phase.phase {
        case "New Moon":
            return "Dark skies tonight if cloud cover cooperates."
        case "Waxing Crescent", "Waning Crescent":
            return "A slimmer moon keeps the sky relatively dark for evening viewing."
        case "First Quarter", "Last Quarter":
            return "Half-lit moonlight adds some brightness without washing everything out."
        case "Full Moon":
            return "Expect bright moonlight and less contrast in the night sky."
        default:
            return "Moonlight will be noticeable for most night plans today."
        }
    }

    private func moonPrimaryStatus(for phase: MoonPhase) -> String {
        switch phase.phase {
        case "New Moon":
            return "Darkest night window"
        case "Waxing Crescent", "Waning Crescent":
            return "Lower moonlight"
        case "First Quarter", "Last Quarter":
            return "Balanced moonlight"
        case "Full Moon":
            return "Bright moonlight"
        default:
            return "Moderate moonlight"
        }
    }

    private func clampSelectedDayIndex() {
        selectedDayIndex = weather.dailyForecast.isEmpty ? 0 : min(selectedDayIndex, weather.dailyForecast.count - 1)
    }
}

struct AstronomyStatTile: View {
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

