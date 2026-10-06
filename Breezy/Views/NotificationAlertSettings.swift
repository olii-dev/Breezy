//
//  NotificationAlertSettings.swift
//  Breezy
//
//  Per-alert customization pages (threshold, cooldown, sound, content) and the
//  Live Activities settings section.
//

import SwiftUI
import UserNotifications

// MARK: - Alert Detail Page

/// One alert type's full customization, all in one place: enable toggle,
/// threshold, cooldown, sound and notification content.
struct AlertDetailSettingsView: View {
    @Binding var settings: NotificationSettings
    @ObservedObject var viewModel: WeatherViewModel
    let config: AlertDetailConfig
    var onSave: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showAddTimeSheet = false

    struct AlertDetailConfig {
        enum Threshold { case uv, rainChance, temperatureChange, windSpeed, rainProbability }
        enum Cooldown { case rain, uv, wind, severe }
        enum Content { case daily, severe, alerts }

        let title: String
        let icon: String
        let color: Color
        var threshold: Threshold? = nil
        var cooldown: Cooldown? = nil
        let soundPath: WritableKeyPath<NotificationSettings, SoundOption>
        var content: Content? = nil
        var isDailyForecast = false
    }

    var body: some View {
        let theme = viewModel.currentTheme(colorScheme: colorScheme)

        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.spacingL) {
                // Header + enable
                HStack(spacing: 12) {
                    Image(systemName: config.icon)
                        .font(.title2)
                        .foregroundColor(config.color)
                    Text(config.title)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(theme.textColor)
                    Spacer()
                }
                .padding()
                .background(cardBackground)

                // Threshold
                if let threshold = config.threshold {
                    thresholdCard(threshold, theme: theme)
                }

                // Cooldown
                if let cooldown = config.cooldown {
                    cooldownCard(cooldown, theme: theme)
                }

                // Daily forecast scheduling
                if config.isDailyForecast {
                    dailyForecastCard(theme: theme)
                }

                // Sound
                soundCard(theme: theme)

                // Content
                if let content = config.content {
                    contentCard(content, theme: theme)
                }
            }
            .padding()
        }
        .background(
            AnimatedGradientBackground(colors: [theme.topColor, theme.bottomColor])
        )
        .navigationTitle(config.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Cards

    private func thresholdCard(_ threshold: AlertDetailConfig.Threshold, theme: WeatherTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch threshold {
            case .uv:
                sliderHeader("Threshold", systemImage: "sun.max.fill", value: "\(settings.uvThreshold)+", tint: .yellow, theme: theme)
                slider($settings.uvThreshold, range: 3...11, step: 1, tint: .yellow)
                caption("Alert when the UV index reaches this level", theme: theme)

            case .rainChance:
                sliderHeader("Rain Chance Threshold", systemImage: "cloud.rain.fill", value: "\(settings.rainChanceThreshold)%", tint: .blue, theme: theme)
                slider($settings.rainChanceThreshold, range: 10...90, step: 10, tint: .blue)
                caption("Used when no minute-by-minute rain data is available", theme: theme)

            case .temperatureChange:
                sliderHeader("Change Threshold", systemImage: "thermometer.variable", value: "\(settings.temperatureChangeThreshold)°", tint: .orange, theme: theme)
                slider($settings.temperatureChangeThreshold, range: 5...20, step: 1, tint: .orange)
                caption("Alert when the temperature swings this much from yesterday", theme: theme)

            case .windSpeed:
                sliderHeader("Wind Threshold", systemImage: "wind", value: "\(settings.windSpeedThreshold) \(viewModel.windSpeedUnit.displayName)", tint: .cyan, theme: theme)
                slider($settings.windSpeedThreshold, range: 20...80, step: 5, tint: .cyan)
                caption("Alert when wind speeds reach this level", theme: theme)

            case .rainProbability:
                sliderHeader("Rain Probability", systemImage: "cloud.drizzle.fill", value: "\(settings.precipitationProbabilityThreshold)%", tint: .teal, theme: theme)
                slider($settings.precipitationProbabilityThreshold, range: 30...100, step: 10, tint: .teal)
                caption("Alert when the day's rain probability reaches this percentage", theme: theme)
            }
        }
        .padding()
        .background(cardBackground)
    }

    private func cooldownCard(_ cooldown: AlertDetailConfig.Cooldown, theme: WeatherTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch cooldown {
            case .rain:
                sliderHeader("Cooldown", systemImage: "clock.fill", value: "\(settings.rainAlertCooldownMinutes)m", tint: .blue, theme: theme)
                slider($settings.rainAlertCooldownMinutes, range: 5...60, step: 5, tint: .blue)
                caption("Minimum time between rain alerts", theme: theme)

            case .uv:
                sliderHeader("Cooldown", systemImage: "clock.fill", value: "\(settings.uvAlertCooldownMinutes / 60)h", tint: .yellow, theme: theme)
                slider($settings.uvAlertCooldownMinutes, range: 60...360, step: 60, tint: .yellow)
                caption("Minimum time between UV alerts for the same location", theme: theme)

            case .wind:
                sliderHeader("Cooldown", systemImage: "clock.fill", value: "\(settings.windAlertCooldownMinutes)m", tint: .cyan, theme: theme)
                slider($settings.windAlertCooldownMinutes, range: 15...180, step: 15, tint: .cyan)
                caption("Minimum time between wind alerts", theme: theme)

            case .severe:
                sliderHeader("Re-alert Interval", systemImage: "clock.fill", value: "\(settings.severeWeatherAlertCooldownMinutes / 60)h", tint: .red, theme: theme)
                slider($settings.severeWeatherAlertCooldownMinutes, range: 30...360, step: 30, tint: .red)
                caption("How often severe weather can re-alert while a warning persists", theme: theme)
            }
        }
        .padding()
        .background(cardBackground)
    }

    private func dailyForecastCard(theme: WeatherTheme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("Forecast Time", selection: Binding(
                get: {
                    let c = Calendar.current
                    var comps = DateComponents()
                    comps.hour = settings.dailyForecastTimes.first?.hour ?? settings.dailyForecastHour
                    comps.minute = settings.dailyForecastTimes.first?.minute ?? settings.dailyForecastMinute
                    return c.date(from: comps) ?? Date()
                },
                set: {
                    HapticsManager.shared.selectionChanged()
                    let c = Calendar.current
                    let hour = c.component(.hour, from: $0)
                    let minute = c.component(.minute, from: $0)
                    settings.dailyForecastHour = hour
                    settings.dailyForecastMinute = minute
                    if settings.dailyForecastTimes.isEmpty {
                        settings.dailyForecastTimes = [ForecastTime(hour: hour, minute: minute)]
                    } else {
                        settings.dailyForecastTimes[0] = ForecastTime(hour: hour, minute: minute)
                    }
                    onSave()
                }
            ), displayedComponents: .hourAndMinute)

            Divider()

            ForEach(Array(settings.dailyForecastTimes.enumerated()), id: \.offset) { index, time in
                HStack {
                    Text(String(format: "%02d:%02d", time.hour, time.minute))
                        .foregroundColor(theme.textColor)
                    Spacer()
                    if settings.dailyForecastTimes.count > 1 {
                        Button {
                            HapticsManager.shared.selectionChanged()
                            settings.dailyForecastTimes.remove(at: index)
                            onSave()
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                    }
                }
            }

            Button {
                HapticsManager.shared.selectionChanged()
                showAddTimeSheet = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Time")
                }
                .foregroundColor(.blue)
            }
            .sheet(isPresented: $showAddTimeSheet) {
                AddForecastTimeView(settings: $settings) { newTime in
                    // Cancel passes a -1 hour sentinel; only real times append.
                    if newTime.hour >= 0 {
                        settings.dailyForecastTimes.append(newTime)
                        onSave()
                    }
                }
            }

            Divider()

            Toggle(isOn: Binding(
                get: { settings.onlyWeekdayForecast },
                set: { settings.onlyWeekdayForecast = $0; onSave() }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weekdays Only")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(theme.textColor)
                    Text("Skip the weekend forecast")
                        .font(.caption2)
                        .foregroundColor(theme.textColor.opacity(0.5))
                }
            }
            .tint(config.color)
        }
        .padding()
        .background(cardBackground)
    }

    private func soundCard(theme: WeatherTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sound", systemImage: "speaker.wave.2.fill")
                .font(.subheadline.weight(.medium))
                .foregroundColor(theme.textColor)

            Picker("", selection: Binding(
                get: { settings[keyPath: config.soundPath] },
                set: { settings[keyPath: config.soundPath] = $0; onSave() }
            )) {
                ForEach(SoundOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .background(cardBackground)
    }

    private func contentCard(_ content: AlertDetailConfig.Content, theme: WeatherTheme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let preference: Binding<NotificationContentPreference> = Binding(
                get: {
                    switch content {
                    case .daily: return settings.dailyForecastContent
                    case .severe: return settings.severeWeatherContent
                    case .alerts: return settings.alertContent
                    }
                },
                set: { newValue in
                    switch content {
                    case .daily: settings.dailyForecastContent = newValue
                    case .severe: settings.severeWeatherContent = newValue
                    case .alerts: settings.alertContent = newValue
                    }
                    onSave()
                }
            )

            NotificationContentEditor(
                title: "Notification Content",
                subtitle: "Choose which details appear in this alert.",
                preference: preference,
                theme: theme
            )
        }
        .padding()
        .background(cardBackground)
    }

    // MARK: - Pieces

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: DesignSystem.radiusM)
            .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
    }

    private func sliderHeader(_ title: String, systemImage: String, value: String, tint: Color, theme: WeatherTheme) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundColor(theme.textColor)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(tint)
        }
    }

    private func slider(_ value: Binding<Int>, range: ClosedRange<Double>, step: Double, tint: Color) -> some View {
        Slider(
            value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0); onSave() }
            ),
            in: range,
            step: step
        )
        .tint(tint)
    }

    private func caption(_ text: String, theme: WeatherTheme) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundColor(theme.textColor.opacity(0.5))
    }
}

// MARK: - Content Editor (shared component)

struct NotificationContentEditor: View {
    let title: String
    let subtitle: String
    @Binding var preference: NotificationContentPreference
    let theme: WeatherTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(theme.textColor)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(theme.textColor.opacity(0.6))
            }

            contentToggle("Condition", \.includeCondition)
            contentToggle("Temperature Range", \.includeTemperatureRange)
            contentToggle("Humidity", \.includeHumidity)
            contentToggle("Wind Speed", \.includeWindSpeed)
            contentToggle("Feels Like", \.includeFeelsLike)
            contentToggle("UV Index", \.includeUVIndex)
            contentToggle("Rain Chance", \.includeRainChance)
            contentToggle("Visibility", \.includeVisibility)
        }
    }

    private func contentToggle(_ title: String, _ keyPath: WritableKeyPath<NotificationContentPreference, Bool>) -> some View {
        Button {
            preference[keyPath: keyPath].toggle()
            HapticsManager.shared.selectionChanged()
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundColor(theme.textColor)
                Spacer()
                Image(systemName: preference[keyPath: keyPath] ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(preference[keyPath: keyPath] ? DesignSystem.skyBlue : theme.textColor.opacity(0.35))
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Live Activities Settings

struct LiveActivitySettingsView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) private var colorScheme

    private struct ActivityRow {
        let title: String
        let icon: String
        let color: Color
        let caption: String
        let key: String
        let onDisable: () -> Void
    }

    var body: some View {
        let theme = viewModel.currentTheme(colorScheme: colorScheme)

        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.spacingL) {
                Text("Live Activities show on your Lock Screen and in Dynamic Island while the weather matters — no notifications needed.")
                    .font(.caption)
                    .foregroundColor(theme.textColor.opacity(0.6))

                VStack(spacing: DesignSystem.spacingS) {
                    ForEach(activityRows, id: \.title) { row in
                        activityToggle(row, theme: theme)
                    }
                }

                Text("Live Activities need to be allowed for Breezy in Settings → Notifications → Live Activities.")
                    .font(.caption2)
                    .foregroundColor(theme.textColor.opacity(0.4))
            }
            .padding()
        }
        .background(
            AnimatedGradientBackground(colors: [theme.topColor, theme.bottomColor])
        )
        .navigationTitle("Live Activities")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var activityRows: [ActivityRow] {
        [
            ActivityRow(
                title: "Rain Countdown",
                icon: "cloud.rain.fill",
                color: .cyan,
                caption: "Counts down to rain arriving within two hours.",
                key: "Breezy.rainLiveActivityEnabled",
                onDisable: { RainLiveActivityManager.shared.end() }
            ),
            ActivityRow(
                title: "UV Protection",
                icon: "sun.max.fill",
                color: .yellow,
                caption: "Shows the UV index while it's high, and when it drops.",
                key: "Breezy.uvLiveActivityEnabled",
                onDisable: { UVLiveActivityManager.shared.end() }
            ),
            ActivityRow(
                title: "Severe Weather",
                icon: "exclamationmark.triangle.fill",
                color: .red,
                caption: "A persistent warning while severe weather is possible.",
                key: "Breezy.severeLiveActivityEnabled",
                onDisable: { SevereWeatherLiveActivityManager.shared.end() }
            ),
            ActivityRow(
                title: "High Wind",
                icon: "wind",
                color: .teal,
                caption: "Tracks strong winds until they ease.",
                key: "Breezy.windLiveActivityEnabled",
                onDisable: { WindLiveActivityManager.shared.end() }
            ),
            ActivityRow(
                title: "Daily Forecast Card",
                icon: "sun.horizon.fill",
                color: .orange,
                caption: "Today's summary for about 90 minutes after your forecast time.",
                key: "Breezy.dailySummaryLiveActivityEnabled",
                onDisable: { DailySummaryLiveActivityManager.shared.end() }
            )
        ]
    }

    private func activityToggle(_ row: ActivityRow, theme: WeatherTheme) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: row.icon)
                .font(.title3)
                .foregroundColor(row.color)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(theme.textColor)
                Text(row.caption)
                    .font(.caption2)
                    .foregroundColor(theme.textColor.opacity(0.5))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: Binding(
                get: { UserDefaults.standard.object(forKey: row.key) as? Bool ?? true },
                set: { newValue in
                    UserDefaults.standard.set(newValue, forKey: row.key)
                    if !newValue {
                        row.onDisable()
                    }
                }
            ))
            .labelsHidden()
            .tint(row.color)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
        )
    }
}
