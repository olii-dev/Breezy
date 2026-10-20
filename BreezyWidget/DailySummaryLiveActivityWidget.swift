//
//  DailySummaryLiveActivityWidget.swift
//  BreezyWidget
//
//  Live Activity / Dynamic Island — today's forecast summary card. Deliberately
//  time-boxed: it appears after the daily forecast time and dismisses itself.
//

import WidgetKit
import SwiftUI
import ActivityKit

struct DailySummaryLiveActivityWidget: Widget {
    /// User-picked accent (Live Activity settings) or the family default.
    private var accent: Color { LiveActivityTheme.accent(activity: "daily", fallback: accent) }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DailySummaryActivityAttributes.self) { context in
            lockScreenView(context: context)
                .padding()
                .widgetURL(URL(string: "breezy://alerts"))
                .activityBackgroundTint(LiveActivityTheme.backgroundTint(accent: .cyan))
                .activitySystemActionForegroundColor(LiveActivityTheme.foregroundColor())
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.dayLabel)
                            .font(.headline)
                            .foregroundStyle(accent)
                        Text(context.attributes.cityName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.highLowText)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.conditionText)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let rain = context.state.rainChanceText {
                            Label(rain, systemImage: "cloud.rain.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Have a great day!")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "sun.horizon.fill")
                    .foregroundStyle(accent)
            } compactTrailing: {
                Text(context.state.highLowText)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 64)
            } minimal: {
                Image(systemName: "sun.horizon.fill")
                    .foregroundStyle(accent)
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<DailySummaryActivityAttributes>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "sun.horizon.fill")
                .font(.title2)
                .foregroundStyle(accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(context.attributes.dayLabel) in \(context.attributes.cityName)")
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(context.state.conditionText)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    if let rain = context.state.rainChanceText {
                        Text("· \(rain)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            Text(context.state.highLowText)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(accent)
                .lineLimit(1)
        }
    }
}
