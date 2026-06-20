import SwiftUI
import Charts
import WeatherKit
import CoreLocation

struct WatchTimeMachineView: View {
    @EnvironmentObject var viewModel: WatchWeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    @State private var historicalData: WatchHistoricalDay?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var doubleTapSectionIndex = 0
    
    private var selectedSource: WatchSelectedWeatherSource {
        let defaults = UserDefaults(suiteName: WatchAppStorageKey.appGroup) ?? .standard
        return defaults.string(forKey: WatchAppStorageKey.weatherSource)
            .flatMap(WatchSelectedWeatherSource.init(rawValue:))
            ?? defaults.string(forKey: WatchAppStorageKey.phoneWeatherSource)
                .flatMap(WatchSelectedWeatherSource.init(rawValue:))
            ?? .weatherKit
    }

    private var minDate: Date { selectedSource.historicalStartDate }
    private var isAtEarliestDate: Bool { Calendar.current.isDate(selectedDate, inSameDayAs: minDate) }
    private var isAtLatestDate: Bool { Calendar.current.isDate(selectedDate, inSameDayAs: Date()) }
    private var theme: WatchWeatherTheme {
        viewModel.currentTheme(isSystemDark: colorScheme == .dark)
    }
    private var scrollSectionIDs: [String] {
        var ids = ["top", "picker", "fetch"]
        if historicalData != nil || errorMessage != nil {
            ids.append("result")
        }
        return ids
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    Text("TIME MACHINE")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(theme.textColor.opacity(0.9))
                        .padding(.top, 4)
                        .id("top")
                    
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            dateStepperButton(systemName: "chevron.left", disabled: isAtEarliestDate) {
                                shiftDate(by: -1)
                            }

                            VStack(spacing: 4) {
                                Text(selectedDate, format: .dateTime.weekday(.wide))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(theme.textColor.opacity(0.72))

                                Text(selectedDate, format: .dateTime.day().month(.abbreviated).year())
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .minimumScaleFactor(0.75)
                                    .lineLimit(1)
                                    .foregroundColor(theme.textColor)
                            }
                            .frame(maxWidth: .infinity)

                            dateStepperButton(systemName: "chevron.right", disabled: isAtLatestDate) {
                                shiftDate(by: 1)
                            }
                        }

                        if !isAtLatestDate {
                            Button("Jump to Today") {
                                selectedDate = Calendar.current.startOfDay(for: Date())
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(theme.textColor.opacity(0.82))
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                    .background(theme.textColor.opacity(0.15))
                    .cornerRadius(14)
                    .id("picker")
                    
                    Button {
                        fetchHistory()
                    } label: {
                        HStack(spacing: 6) {
                            if isLoading {
                                ProgressView()
                                    .tint(theme.textColor)
                            } else {
                                Image(systemName: "clock.arrow.circlepath")
                            }
                            Text("Fetch")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(theme.textColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(theme.textColor.opacity(0.2))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                    .id("fetch")
                    
                    Group {
                        if let data = historicalData {
                            historicalResultView(data: data, theme: theme)
                        } else if let errorMessage {
                            VStack(spacing: 8) {
                                Image(systemName: "cloud.slash")
                                    .font(.system(size: 28))
                                    .foregroundColor(theme.textColor.opacity(0.75))
                                Text(errorMessage)
                                    .font(.system(size: 12, weight: .medium))
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(theme.textColor.opacity(0.8))
                            }
                            .padding(12)
                            .background(theme.textColor.opacity(0.15))
                            .cornerRadius(10)
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 30))
                                    .foregroundColor(theme.textColor.opacity(0.7))
                                Text("Select a date to see past weather")
                                    .font(.system(size: 12, weight: .medium))
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(theme.textColor.opacity(0.75))
                                Text(selectedSource.historicalAvailabilityDescription)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(theme.textColor.opacity(0.7))
                            }
                            .padding(16)
                        }
                    }
                    .id("result")
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .overlay(alignment: .topTrailing) {
                WatchDoubleTapScrollTrigger {
                    scrollToNextSection(using: proxy)
                }
            }
        }
        .focusable()
    }

    private func scrollToNextSection(using proxy: ScrollViewProxy) {
        guard scrollSectionIDs.count > 1 else { return }
        let nextIndex = doubleTapSectionIndex >= scrollSectionIDs.count - 1 ? 0 : doubleTapSectionIndex + 1
        doubleTapSectionIndex = nextIndex
        withAnimation(.easeInOut(duration: 0.28)) {
            proxy.scrollTo(scrollSectionIDs[nextIndex], anchor: .top)
        }
    }
    
    @ViewBuilder
    private func historicalResultView(data: WatchHistoricalDay, theme: WatchWeatherTheme) -> some View {
        VStack(spacing: 8) {
            Text(formatDate(data.date).uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(theme.textColor.opacity(0.8))
            
            HStack(spacing: 12) {
                if viewModel.useMinimalistIcons {
                    Image(systemName: data.iconName)
                        .font(.system(size: 32))
                        .foregroundColor(theme.textColor)
                } else {
                    Text(data.emoji)
                        .font(.system(size: 32))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(data.condition)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(theme.textColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    HStack(spacing: 10) {
                        Text("H: \(data.highTemp)")
                        Text("L: \(data.lowTemp)")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.textColor.opacity(0.85))
                }
            }
            
            if !data.hourlyTemps.isEmpty {
                Chart {
                    ForEach(data.hourlyTemps) { point in
                        LineMark(
                            x: .value("Hour", point.index),
                            y: .value("Temp", point.temp)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.orange)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: 6)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(theme.textColor.opacity(0.15))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(theme.textColor.opacity(0.15))
                    }
                }
                .frame(height: 60)
                .padding(.top, 4)
            }
            
            if let precip = data.precipChance {
                HStack {
                    Image(systemName: "cloud.rain.fill")
                        .font(.caption2)
                    Text("Rain: \(precip)")
                        .font(.system(size: 11))
                }
                .foregroundColor(theme.textColor.opacity(0.75))
            }
            
            if let wind = data.maxWind {
                HStack {
                    Image(systemName: "wind")
                        .font(.caption2)
                    Text("Wind: \(wind)")
                        .font(.system(size: 11))
                }
                .foregroundColor(theme.textColor.opacity(0.75))
            }
        }
        .padding(12)
        .background(theme.textColor.opacity(0.12))
        .cornerRadius(12)
    }
    
    private func fetchHistory() {
        isLoading = true
        errorMessage = nil
        historicalData = nil
        
        Task {
            do {
                let result = try await fetchHistoricalWeather(for: selectedDate)
                historicalData = result
            } catch {
                errorMessage = "No data available for this date. \(selectedSource.historicalAvailabilityDescription)."
            }
            isLoading = false
        }
    }

    private func shiftDate(by days: Int) {
        let calendar = Calendar.current
        let shifted = calendar.date(byAdding: .day, value: days, to: selectedDate) ?? selectedDate
        let latest = calendar.startOfDay(for: Date())
        selectedDate = min(max(shifted, minDate), latest)
    }

    private func dateStepperButton(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(theme.textColor.opacity(disabled ? 0.3 : 0.9))
                .frame(width: 30, height: 30)
                .background(theme.textColor.opacity(disabled ? 0.06 : 0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
    
    private func fetchHistoricalWeather(for date: Date) async throws -> WatchHistoricalDay {
        let location: CLLocation
        if let weather = viewModel.weather,
           let lat = weather.metadata.latitude,
           let lon = weather.metadata.longitude {
            location = CLLocation(latitude: lat, longitude: lon)
        } else {
            let helper = WatchLocationHelper()
            let gpsData = try await helper.requestLocationAndGetData()
            location = CLLocation(latitude: gpsData.latitude, longitude: gpsData.longitude)
        }
        
        let defaults = UserDefaults(suiteName: WatchAppStorageKey.appGroup) ?? .standard
        let temperatureUnit = defaults.string(forKey: WatchAppStorageKey.temperatureUnit)
            .flatMap(WatchTemperatureUnit.init(rawValue:))
            ?? .celsius
        let windUnit = defaults.string(forKey: WatchAppStorageKey.windSpeedUnit)
            .flatMap(WindSpeedUnit.init(rawValue:))
            ?? .metersPerSecond

        switch selectedSource {
        case .weatherKit:
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            let weatherService = WeatherService.shared
            let daily = try await weatherService.weather(for: location, including: .daily(startDate: date, endDate: endOfDay))
            let hourly = try await weatherService.weather(for: location, including: .hourly(startDate: startOfDay, endDate: endOfDay))

            guard let dayForecast = daily.first else {
                throw NSError(domain: "WatchTimeMachine", code: 1, userInfo: [NSLocalizedDescriptionKey: "No data"])
            }

            let isFahrenheit = temperatureUnit == .fahrenheit
            let suffix = isFahrenheit ? "°F" : "°C"
            let highVal = isFahrenheit ? dayForecast.highTemperature.converted(to: UnitTemperature.fahrenheit).value : dayForecast.highTemperature.converted(to: UnitTemperature.celsius).value
            let lowVal = isFahrenheit ? dayForecast.lowTemperature.converted(to: UnitTemperature.fahrenheit).value : dayForecast.lowTemperature.converted(to: UnitTemperature.celsius).value

            let hourlyTemps: [WatchTempPoint] = hourly.enumerated().compactMap { index, hour in
                let temp = isFahrenheit ? hour.temperature.converted(to: UnitTemperature.fahrenheit).value : hour.temperature.converted(to: UnitTemperature.celsius).value
                return WatchTempPoint(index: index, temp: temp)
            }

            let condition = WatchWeatherConditionConverter.description(from: dayForecast.condition)

            return WatchHistoricalDay(
                date: date,
                condition: condition,
                emoji: WatchWeatherIconHelper.emoji(for: condition),
                iconName: WatchWeatherIconHelper.minimalistIcon(for: condition),
                highTemp: String(format: "%.0f%@", highVal, suffix),
                lowTemp: String(format: "%.0f%@", lowVal, suffix),
                precipChance: dayForecast.precipitationChance > 0 ? String(format: "%.0f%%", dayForecast.precipitationChance * 100) : nil,
                maxWind: nil,
                hourlyTemps: hourlyTemps
            )
        case .openMeteo:
            return try await WatchOpenMeteoClient.shared.fetchHistoricalDay(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                date: date,
                temperatureUnit: temperatureUnit,
                windUnit: windUnit
            )
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }
}
