//
//  RainLiveActivityWidget.swift
//  BreezyWidget
//
//  Live Activity / Dynamic Island — while rain is approaching the current
//  location. Countdown runs client-side from the forecast start time.
//

import WidgetKit
import SwiftUI
import ActivityKit

struct RainLiveActivityWidget: Widget {
    /// User-picked accent (Live Activity settings) or the family default.
    private var accent: Color { LiveActivityTheme.accent(activity: "rain", fallback: .cyan) }

    private func on(_ element: String) -> Bool {
        LiveActivityElements.isEnabled(activity: "rain", element: element)
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RainActivityAttributes.self) { context in
            lockScreenView(context: context)
                .padding()
                .widgetURL(URL(string: "breezy://alerts"))
                .activityBackgroundTint(LiveActivityTheme.backgroundTint(accent: accent))
                .activitySystemActionForegroundColor(LiveActivityTheme.foregroundColor())
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Rain", systemImage: "cloud.rain.fill")
                            .font(.headline)
                            .foregroundStyle(accent)
                        if on("chance") {
                            Text("\(context.state.chancePercent)% chance")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(timerInterval: Date()...max(Date().addingTimeInterval(60), context.state.rainStart), countsDown: true)
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(accent)
                        Text("until rain")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.cityName)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if on("intensity"), let intensity = context.state.intensityText {
                            Text(intensity)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if on("window") {
                            Text(context.state.rainEnd.map { end in
                                "From \(context.state.rainStart.formatted(date: .omitted, time: .shortened)) until \(end.formatted(date: .omitted, time: .shortened))"
                            } ?? "From \(context.state.rainStart.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "cloud.rain.fill")
                    .foregroundStyle(accent)
            } compactTrailing: {
                Text(timerInterval: Date()...max(Date().addingTimeInterval(60), context.state.rainStart), countsDown: true)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "cloud.rain.fill")
                    .foregroundStyle(accent)
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<RainActivityAttributes>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "cloud.rain.fill")
                .font(.title2)
                .foregroundStyle(accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Rain approaching \(context.attributes.cityName)")
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if on("chance") {
                        Text("\(context.state.chancePercent)%")
                            .font(.caption.weight(.semibold))
                    }
                    if on("intensity"), let intensity = context.state.intensityText {
                        Text(intensity)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if on("window") {
                        Text("· from \(context.state.rainStart.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(timerInterval: Date()...max(Date().addingTimeInterval(60), context.state.rainStart), countsDown: true)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                Text("until rain")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
