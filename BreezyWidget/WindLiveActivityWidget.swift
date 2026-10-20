//
//  WindLiveActivityWidget.swift
//  BreezyWidget
//
//  Live Activity / Dynamic Island — while winds are strong.
//

import WidgetKit
import SwiftUI
import ActivityKit

struct WindLiveActivityWidget: Widget {

    /// User-picked accent (Live Activity settings) or the family default.
    private var accent: Color { LiveActivityTheme.accent(activity: "wind", fallback: .teal) }

    private func on(_ element: String) -> Bool {
        LiveActivityElements.isEnabled(activity: "wind", element: element)
    }
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WindActivityAttributes.self) { context in
            lockScreenView(context: context)
                .padding()
                .widgetURL(URL(string: "breezy://alerts"))
                .activityBackgroundTint(LiveActivityTheme.backgroundTint(accent: accent))
                .activitySystemActionForegroundColor(LiveActivityTheme.foregroundColor())
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Wind", systemImage: "wind")
                            .font(.headline)
                            .foregroundStyle(accent)
                        if on("direction"), let direction = context.state.directionText {
                            Text(direction)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.speedText)
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(accent)
                        if on("gust"), let gust = context.state.gustText {
                            Text(gust)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.cityName)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if on("direction"), let direction = context.state.directionText {
                            Text(direction)
                                .font(.caption)
                                .foregroundStyle(accent)
                        }
                        Spacer()
                        Text("Take care outdoors — secure loose items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            } compactLeading: {
                Image(systemName: "wind")
                    .foregroundStyle(accent)
            } compactTrailing: {
                Text(context.state.speedText)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "wind")
                    .foregroundStyle(accent)
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<WindActivityAttributes>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "wind")
                .font(.title2)
                .foregroundStyle(accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Strong winds in \(context.attributes.cityName)")
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if on("direction"), let direction = context.state.directionText {
                        Text(direction)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if on("gust"), let gust = context.state.gustText {
                        Text("· \(gust)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(context.state.speedText)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                Text("wind")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
