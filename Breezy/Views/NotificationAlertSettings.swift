//
//  NotificationAlertSettings.swift
//  Breezy
//
//  Per-alert customization pages (threshold, cooldown, sound, content) and the
//  Live Activities settings section.
//

import SwiftUI
import UserNotifications
import WidgetKit

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
                slider($settings.uvThreshold, range: 3...11, step: 1, tint: .yellow, label: "UV threshold", unit: "index")
                caption("Alert when the UV index reaches this level", theme: theme)

            case .rainChance:
                sliderHeader("Rain Chance Threshold", systemImage: "cloud.rain.fill", value: "\(settings.rainChanceThreshold)%", tint: .blue, theme: theme)
                slider($settings.rainChanceThreshold, range: 10...90, step: 10, tint: .blue, label: "Rain chance threshold", unit: "percent")
                caption("Used when no minute-by-minute rain data is available", theme: theme)

            case .temperatureChange:
                sliderHeader("Change Threshold", systemImage: "thermometer.variable", value: "\(settings.temperatureChangeThreshold)°", tint: .orange, theme: theme)
                slider($settings.temperatureChangeThreshold, range: 5...20, step: 1, tint: .orange, label: "Temperature change threshold", unit: "degrees")
                caption("Alert when the temperature swings this much from yesterday", theme: theme)

            case .windSpeed:
                sliderHeader("Wind Threshold", systemImage: "wind", value: "\(settings.windSpeedThreshold) \(viewModel.windSpeedUnit.displayName)", tint: .cyan, theme: theme)
                slider($settings.windSpeedThreshold, range: 20...80, step: 5, tint: .cyan, label: "Wind threshold")
                caption("Alert when wind speeds reach this level", theme: theme)

            case .rainProbability:
                sliderHeader("Rain Probability", systemImage: "cloud.drizzle.fill", value: "\(settings.precipitationProbabilityThreshold)%", tint: .teal, theme: theme)
                slider($settings.precipitationProbabilityThreshold, range: 30...100, step: 10, tint: .teal, label: "Rain probability threshold", unit: "percent")
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
                slider($settings.rainAlertCooldownMinutes, range: 5...60, step: 5, tint: .blue, label: "Rain alert cooldown", unit: "minutes")
                caption("Minimum time between rain alerts", theme: theme)

            case .uv:
                sliderHeader("Cooldown", systemImage: "clock.fill", value: "\(settings.uvAlertCooldownMinutes / 60)h", tint: .yellow, theme: theme)
                slider($settings.uvAlertCooldownMinutes, range: 60...360, step: 60, tint: .yellow, label: "UV alert cooldown", unit: "minutes")
                caption("Minimum time between UV alerts for the same location", theme: theme)

            case .wind:
                sliderHeader("Cooldown", systemImage: "clock.fill", value: "\(settings.windAlertCooldownMinutes)m", tint: .cyan, theme: theme)
                slider($settings.windAlertCooldownMinutes, range: 15...180, step: 15, tint: .cyan, label: "Wind alert cooldown", unit: "minutes")
                caption("Minimum time between wind alerts", theme: theme)

            case .severe:
                sliderHeader("Re-alert Interval", systemImage: "clock.fill", value: "\(settings.severeWeatherAlertCooldownMinutes / 60)h", tint: .red, theme: theme)
                slider($settings.severeWeatherAlertCooldownMinutes, range: 30...360, step: 30, tint: .red, label: "Severe re-alert interval", unit: "minutes")
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

            Picker("Sound", selection: Binding(
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

    private func slider(_ value: Binding<Int>, range: ClosedRange<Double>, step: Double, tint: Color, label: String, unit: String = "") -> some View {
        Slider(
            value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0); onSave() }
            ),
            in: range,
            step: step
        )
        .tint(tint)
        .accessibilityLabel(label)
        .accessibilityValue("\(value.wrappedValue)\(unit.isEmpty ? "" : " \(unit)")")
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

// MARK: - Lightning Alert Settings

/// Lightning alerts' two prongs explained — no thresholds to tune.
struct LightningAlertSettingsView: View {
    @Binding var settings: NotificationSettings
    @ObservedObject var viewModel: WeatherViewModel
    var onSave: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = viewModel.currentTheme(colorScheme: colorScheme)

        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.spacingL) {
                HStack(spacing: 12) {
                    Image(systemName: "bolt.fill")
                        .font(.title2)
                        .foregroundColor(.yellow)
                    Text("Lightning Alerts")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(theme.textColor)
                    Spacer()
                }
                .padding()
                .background(cardBackground)

                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: Binding(
                        get: { settings.lightningAlertsEnabled },
                        set: { settings.lightningAlertsEnabled = $0; onSave() }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enabled")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(theme.textColor)
                            Text("Ignores quiet hours — lightning is a safety alert")
                                .font(.caption2)
                                .foregroundColor(theme.textColor.opacity(0.5))
                        }
                    }
                    .tint(.yellow)
                }
                .padding()
                .background(cardBackground)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Forecast watch", systemImage: "clock.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(theme.textColor)
                    Text("When thunderstorms appear in the next hour's forecast, you get a \"Lightning Possible\" notification — this works with the app closed, delivered by background refresh.")
                        .font(.caption)
                        .foregroundColor(theme.textColor.opacity(0.6))

                    Label("Live strikes", systemImage: "bolt.horizontal.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(theme.textColor)
                        .padding(.top, 4)
                    Text("While Breezy is open (or the radar is showing) during stormy conditions, the live lightning feed watches for strikes within 20 km and alerts immediately — with stronger wording inside 8 km.")
                        .font(.caption)
                        .foregroundColor(theme.textColor.opacity(0.6))
                }
                .padding()
                .background(cardBackground)
            }
            .padding()
        }
        .background(
            AnimatedGradientBackground(colors: [theme.topColor, theme.bottomColor])
        )
        .navigationTitle("Lightning")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: DesignSystem.radiusM)
            .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
    }
}

// MARK: - Live Activities Settings

struct LiveActivitySettingsView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("Breezy.liveActivityStyle", store: UserDefaults(suiteName: "group.com.breezy.weather"))
    private var liveActivityStyleRaw: String = LiveActivityStyle.darkGlass.rawValue

    /// Swatches/chips read UserDefaults directly; bumping this after a tap
    /// re-evaluates the body so the selected ring and chip states move.
    @State private var customiseSeed = 0

    private struct ActivityCard {
        let activity: String
        let title: String
        let icon: String
        let fallback: Color
        let toggleKey: String
        let caption: String
        let onDisable: () -> Void
    }

    private var activityCards: [ActivityCard] {
        [
            ActivityCard(activity: "rain", title: "Rain Countdown", icon: "cloud.rain.fill", fallback: .cyan,
                         toggleKey: "Breezy.rainLiveActivityEnabled",
                         caption: "Counts down to rain arriving within two hours.",
                         onDisable: { RainLiveActivityManager.shared.end() }),
            ActivityCard(activity: "uv", title: "UV Protection", icon: "sun.max.fill", fallback: .yellow,
                         toggleKey: "Breezy.uvLiveActivityEnabled",
                         caption: "Shows the UV index while it's high, and when it drops.",
                         onDisable: { UVLiveActivityManager.shared.end() }),
            ActivityCard(activity: "severe", title: "Severe Weather", icon: "exclamationmark.triangle.fill", fallback: .red,
                         toggleKey: "Breezy.severeLiveActivityEnabled",
                         caption: "A persistent warning while severe weather is possible.",
                         onDisable: { SevereWeatherLiveActivityManager.shared.end() }),
            ActivityCard(activity: "wind", title: "High Wind", icon: "wind", fallback: .teal,
                         toggleKey: "Breezy.windLiveActivityEnabled",
                         caption: "Tracks strong winds until they ease.",
                         onDisable: { WindLiveActivityManager.shared.end() }),
            ActivityCard(activity: "daily", title: "Daily Forecast Card", icon: "sun.horizon.fill", fallback: .orange,
                         toggleKey: "Breezy.dailySummaryLiveActivityEnabled",
                         caption: "Today's summary for about 90 minutes after your forecast time.",
                         onDisable: { DailySummaryLiveActivityManager.shared.end() }),
            ActivityCard(activity: "aurora", title: "Aurora", icon: "sparkles", fallback: .purple,
                         toggleKey: "Breezy.auroraLiveActivityEnabled",
                         caption: "Space-weather watch card on active nights.",
                         onDisable: { AuroraLiveActivityManager.shared.end() }),
        ]
    }

    var body: some View {
        let theme = viewModel.currentTheme(colorScheme: colorScheme)

        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.spacingL) {
                Text("Live Activities show on your Lock Screen and in Dynamic Island while the weather matters — no notifications needed.")
                    .font(.caption)
                    .foregroundColor(theme.textColor.opacity(0.6))

                VStack(spacing: DesignSystem.spacingS) {
                    ForEach(activityCards, id: \.activity) { card in
                        activityCardView(card, theme: theme)
                            .id(customiseSeed)
                    }
                }

                // Appearance
                VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
                    StudioHeader(title: "APPEARANCE", icon: "paintbrush.fill", theme: theme)

                    Picker("Appearance", selection: $liveActivityStyleRaw) {
                        Text(LiveActivityStyle.darkGlass.displayName).tag(LiveActivityStyle.darkGlass.rawValue)
                        Text(LiveActivityStyle.matchTheme.displayName).tag(LiveActivityStyle.matchTheme.rawValue)
                        Text(LiveActivityStyle.pureBlack.displayName).tag(LiveActivityStyle.pureBlack.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: liveActivityStyleRaw) { _, _ in
                        HapticsManager.shared.selectionChanged()
                        WidgetCenter.shared.reloadAllTimelines()
                    }

                    Text(liveActivityStyleCaption)
                        .font(.caption2)
                        .foregroundColor(theme.textColor.opacity(0.5))
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))

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

    private var liveActivityStyleCaption: String {
        switch LiveActivityStyle(rawValue: liveActivityStyleRaw) {
        case .matchTheme:
            return "Activities use your Custom theme's gradient. Restyles on their next update."
        case .pureBlack:
            return "True-black backgrounds — sharpest on OLED and easiest on battery."
        default:
            return "The classic translucent dark look."
        }
    }

    /// One card per activity: master toggle in the header, expandable
    /// customisation (colour + elements) underneath so the screen stays calm.
    private func activityCardView(_ card: ActivityCard, theme: WeatherTheme) -> some View {
        let isEnabled = UserDefaults.standard.object(forKey: card.toggleKey) as? Bool ?? true

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: card.icon)
                    .font(.title3)
                    .foregroundColor(card.fallback)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(theme.textColor)
                    Text(card.caption)
                        .font(.caption2)
                        .foregroundColor(theme.textColor.opacity(0.5))
                }

                Spacer(minLength: 0)

                Toggle("", isOn: Binding(
                    get: { UserDefaults.standard.object(forKey: card.toggleKey) as? Bool ?? true },
                    set: { newValue in
                        UserDefaults.standard.set(newValue, forKey: card.toggleKey)
                        if !newValue {
                            card.onDisable()
                        }
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                ))
                .labelsHidden()
                .tint(card.fallback)
            }
            .padding()

            if isEnabled {
                Divider()
                    .background(theme.textColor.opacity(0.12))
                VStack(alignment: .leading, spacing: 12) {
                    colourRow(title: card.title, activity: card.activity, fallback: card.fallback, theme: theme)
                }
                .padding()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
        )
        .accessibilityElement(children: .combine)
    }

    private func colourRow(title: String, activity: String, fallback: Color, theme: WeatherTheme) -> some View {
        let currentName = LiveActivityAccent.storedName(activity: activity)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Colour")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(theme.textColor)
                Spacer()
                if currentName != "default" {
                    Button {
                        HapticsManager.shared.selectionChanged()
                        LiveActivityAccent.set("default", activity: activity)
                        WidgetCenter.shared.reloadAllTimelines()
                        customiseSeed += 1
                    } label: {
                        Text("Reset")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(theme.textColor.opacity(0.6))
                    }
                }
            }

            if let elements = LiveActivityElements.catalogue[activity] {
                HStack(spacing: 8) {
                    ForEach(elements, id: \.id) { element in
                        let on = LiveActivityElements.isEnabled(activity: activity, element: element.id)
                        Button {
                            HapticsManager.shared.selectionChanged()
                            LiveActivityElements.set(!on, activity: activity, element: element.id)
                            WidgetCenter.shared.reloadAllTimelines()
                            customiseSeed += 1
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: on ? "checkmark" : "minus")
                                    .font(.caption2.weight(.bold))
                                Text(element.label)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill((on ? Color.green : theme.textColor).opacity(0.12)))
                            .foregroundColor(on ? .green : theme.textColor.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(element.label) for \(title), \(on ? "on" : "off")")
                    }
                    Spacer(minLength: 0)
                }
            }

            // 12 fixed swatches overflow narrow screens and drag the whole
            // card edge-to-edge — deal them a horizontal scroller instead.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(LiveActivityAccent.names, id: \.self) { name in
                        let isDefault = name == "default"
                        let isSelected = currentName == name
                        Button {
                            HapticsManager.shared.selectionChanged()
                            LiveActivityAccent.set(name, activity: activity)
                            WidgetCenter.shared.reloadAllTimelines()
                            customiseSeed += 1
                        } label: {
                            ZStack {
                                if isDefault {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .overlay(Circle().stroke(theme.textColor.opacity(0.4), lineWidth: 1))
                                    Image(systemName: "slash.circle")
                                        .font(.caption2)
                                        .foregroundColor(theme.textColor.opacity(0.7))
                                } else {
                                    Circle().fill(LiveActivityAccent.color(for: name) ?? .gray)
                                }
                                if isSelected {
                                    Circle()
                                        .stroke(theme.textColor, lineWidth: 2)
                                        .frame(width: 30, height: 30)
                                }
                            }
                            .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(isDefault ? "Default" : name) for \(title)")
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                }
            }
            if fallback != .clear {
                HStack(spacing: 4) {
                    Circle()
                        .fill(fallback.opacity(0.35))
                        .frame(width: 10, height: 10)
                    Text("family default: \(fallbackName(fallback))")
                        .font(.caption2)
                        .foregroundColor(theme.textColor.opacity(0.45))
                }
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
    }

    private func fallbackName(_ color: Color) -> String {
        switch color {
        case .cyan: return "Cyan"
        case .yellow: return "Yellow"
        case .red: return "Red"
        case .teal: return "Teal"
        case .orange: return "Orange"
        case .purple: return "Purple"
        default: return "—"
        }
    }
}
