//
//  AuroraAndBriefSettings.swift
//  Breezy
//
//  Settings pages for the aurora alert and the morning brief.
//

import SwiftUI

struct AuroraSettingsView: View {
    @Binding var settings: NotificationSettings
    @ObservedObject var viewModel: WeatherViewModel
    var onSave: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = viewModel.currentTheme(colorScheme: colorScheme)
        let snapshot = AuroraStore.load()

        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.spacingL) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundColor(.purple)
                    Text("Aurora Alerts")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(theme.textColor)
                    Spacer()
                }
                .padding()
                .background(cardBackground)

                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: Binding(
                        get: { settings.auroraAlertsEnabled },
                        set: { settings.auroraAlertsEnabled = $0; onSave() }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enabled")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(theme.textColor)
                            Text("Only when it's dark, clear enough, and Kp clears your latitude")
                                .font(.caption2)
                                .foregroundColor(theme.textColor.opacity(0.5))
                        }
                    }
                    .tint(.purple)

                    if settings.auroraAlertsEnabled {
                        Picker("Minimum Kp", selection: Binding(
                            get: { settings.auroraMinKp },
                            set: { settings.auroraMinKp = $0; onSave() }
                        )) {
                            Text("Automatic by latitude").tag(0)
                            Text("Kp 5+").tag(5)
                            Text("Kp 6+").tag(6)
                            Text("Kp 7+").tag(7)
                            Text("Kp 8+").tag(8)
                        }
                        .pickerStyle(.menu)
                        .foregroundColor(theme.textColor)

                        Text("The picker can only raise the bar — physics decides the floor. Adelaide needs roughly Kp 8; Tasmania sees aurora from Kp 5–6.")
                            .font(.caption2)
                            .foregroundColor(theme.textColor.opacity(0.5))
                    }
                }
                .padding()
                .background(cardBackground)

                // Live snapshot preview
                VStack(alignment: .leading, spacing: 8) {
                    Label("Right now", systemImage: "gauge.with.needle")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(theme.textColor)

                    if let snapshot, let kp = snapshot.kp {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Kp \(AuroraKit.formatted(kp))")
                                    .font(.system(.title3, design: .rounded).weight(.bold))
                                    .foregroundColor(theme.textColor)
                                if let required = snapshot.requiredKp {
                                    Text("needs \(AuroraKit.formatted(required)) at your latitude")
                                        .font(.caption2)
                                        .foregroundColor(theme.textColor.opacity(0.55))
                                }
                            }
                            Spacer()
                            Text(snapshot.verdict)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill((snapshot.isActive ? Color.purple : theme.textColor).opacity(0.15)))
                                .foregroundColor(snapshot.isActive ? .purple : theme.textColor.opacity(0.8))
                        }
                    } else {
                        Text("No space-weather data yet — it pulls with your next forecast.")
                            .font(.caption)
                            .foregroundColor(theme.textColor.opacity(0.55))
                    }
                }
                .padding()
                .background(cardBackground)

                VStack(alignment: .leading, spacing: 8) {
                    Label("How it works", systemImage: "info.circle")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(theme.textColor)
                    Text("Breezy reads NOAA's free space-weather feed (planetary K-index and solar wind) alongside every forecast, then checks darkness, cloud cover and moon brightness before alerting. Like the lightning feed, checks happen when Breezy gets CPU time — the app or background refresh — so treat the alert as a heads-up, not a guarantee.")
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
        .navigationTitle("Aurora")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: DesignSystem.radiusM)
            .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
    }
}

struct MorningBriefSettingsView: View {
    @Binding var settings: NotificationSettings
    @ObservedObject var viewModel: WeatherViewModel
    var onSave: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var briefDate: Binding<Date> {
        Binding(
            get: {
                let time = settings.dailyForecastTimes.first ?? ForecastTime(hour: 7, minute: 0)
                return Calendar.current.date(from: DateComponents(hour: time.hour, minute: time.minute)) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                settings.dailyForecastTimes = [ForecastTime(
                    hour: comps.hour ?? 7,
                    minute: comps.minute ?? 0
                )]
                onSave()
            }
        )
    }

    var body: some View {
        let theme = viewModel.currentTheme(colorScheme: colorScheme)

        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.spacingL) {
                HStack(spacing: 12) {
                    Image(systemName: "sun.and.horizon.fill")
                        .font(.title2)
                        .foregroundColor(.orange)
                    Text("Morning Brief")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(theme.textColor)
                    Spacer()
                }
                .padding()
                .background(cardBackground)

                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: Binding(
                        get: { settings.morningBriefEnabled },
                        set: { settings.morningBriefEnabled = $0; onSave() }
                    )) {
                        Text("Enabled")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(theme.textColor)
                    }
                    .tint(.orange)

                    if settings.morningBriefEnabled {
                        DatePicker(
                            "Delivery time",
                            selection: briefDate,
                            displayedComponents: .hourAndMinute
                        )
                        .foregroundColor(theme.textColor)

                        Text("Replaces the basic daily-forecast notification at this time — the brief covers it, with more useful detail.")
                            .font(.caption2)
                            .foregroundColor(theme.textColor.opacity(0.5))
                    }
                }
                .padding()
                .background(cardBackground)

                VStack(alignment: .leading, spacing: 8) {
                    Label("What's in it", systemImage: "text.bubble")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(theme.textColor)
                    Text("Not a forecast dump — a verdict. Whether today needs an umbrella (from minute-level rain timing), the best dry window for anything outdoors, the UV story, wind flags, golden hour, tides and moon if they matter today, and an aurora line when the sky is worth looking up at. The wording changes with the weather; no two mornings read the same.")
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
        .navigationTitle("Morning Brief")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: DesignSystem.radiusM)
            .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
    }
}
