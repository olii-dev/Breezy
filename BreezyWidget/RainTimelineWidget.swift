//
//  RainTimelineWidget.swift
//  BreezyWidgetExtension
//
//  The WillyWeather-style rain graph: the next ~12 hours as vertical
//  intensity bars (height = expected mm, colour = intensity) with a chance
//  row underneath — rain timing at a glance instead of a single daily %.
//

import WidgetKit
import SwiftUI

struct BreezyRainTimelineWidget: Widget {
    let kind = "BreezyRainTimelineWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            RainTimelineEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Rain Timeline")
        .description("Hour-by-hour rain bars for the next 12 hours — when it starts, how heavy, and when it eases.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Entry view

struct RainTimelineEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeatherEntry

    /// Hours with rain data, oldest first, capped to the family.
    private var hours: [WidgetWeatherData.WidgetHourlyForecast] {
        let limit = family == .systemLarge ? 12 : 8
        return Array(entry.weather.hourlyForecast.filter { $0.precipChance != nil || $0.precipMillimeters != nil }.prefix(limit))
    }

    private var totalMillimeters: Double {
        hours.compactMap(\.precipMillimeters).reduce(0, +)
    }

    private var peakChance: Int {
        Int(((hours.compactMap(\.precipChance).max() ?? 0) * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if hours.isEmpty {
                emptyState
            } else {
                bars
                chanceRow
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(2)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.fill")
                .font(.caption)
                .foregroundStyle(.teal)
            Text("Rain next \(hours.count)h")
                .font(.caption.weight(.bold))
            Spacer()
            if hours.isEmpty {
                EmptyView()
            } else if totalMillimeters >= 0.2 {
                Text(String(format: "%.1f mm · %d%% peak", totalMillimeters, peakChance))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.teal)
            } else {
                Text(peakChance >= 30 ? "Showers possible" : "Mostly dry")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Bars

    private var bars: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: max(3, proxy.size.width / CGFloat(max(hours.count * 5, 1)))) {
                ForEach(Array(hours.enumerated()), id: \.offset) { index, hour in
                    let mm = hour.precipMillimeters ?? 0
                    let chance = hour.precipChance ?? 0

                    // Height ∝ expected mm (capped at 4 mm so storms don't dwarf
                    // everything); colour carries the intensity story.
                    let fraction = min(mm / 4.0, 1)
                    let barColor = intensityColor(mm: mm, chance: chance)

                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(fraction > 0.02 ? barColor : Color.secondary.opacity(0.25))
                            .frame(height: max(3, (proxy.size.height - 14) * fraction))
                            .overlay(alignment: .top) {
                                if index == 0 {
                                    Circle()
                                        .fill(Color.primary)
                                        .frame(width: 3, height: 3)
                                        .offset(y: -2)
                                }
                            }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func intensityColor(mm: Double, chance: Double) -> Color {
        if mm >= 3 { return .indigo }        // heavy
        if mm >= 1 { return .blue }          // steady
        if mm > 0 || chance >= 0.5 { return .cyan } // light/showery
        return .secondary.opacity(0.3)
    }

    // MARK: Chance row

    private var chanceRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(hours.enumerated()), id: \.offset) { index, hour in
                VStack(spacing: 1) {
                    Text(chanceLabel(hour))
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle((hour.precipChance ?? 0) >= 0.5 ? .primary : .secondary)
                        .minimumScaleFactor(0.7)
                    Text(hour.time)
                        .font(.system(size: 7, design: .rounded))
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func chanceLabel(_ hour: WidgetWeatherData.WidgetHourlyForecast) -> String {
        let pct = Int(((hour.precipChance ?? 0) * 100).rounded())
        return pct == 0 ? "·" : "\(pct)"
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 4)
            Image(systemName: "cloud.sun.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No rain signal in the next hours")
                .font(.caption.weight(.semibold))
            Text("Open Breezy for the freshest forecast.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity)
    }
}
