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
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WindActivityAttributes.self) { context in
            lockScreenView(context: context)
                .padding()
                .widgetURL(URL(string: "breezy://alerts"))
                .activityBackgroundTint(LiveActivityTheme.backgroundTint(accent: .cyan))
                .activitySystemActionForegroundColor(LiveActivityTheme.foregroundColor())
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Wind", systemImage: "wind")
                            .font(.headline)
                            .foregroundStyle(.teal)
                        if let direction = context.state.directionText {
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
                            .foregroundStyle(.teal)
                        if let gust = context.state.gustText {
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
                        if let direction = context.state.directionText {
                            Text(direction)
                                .font(.caption)
                                .foregroundStyle(.teal)
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
                    .foregroundStyle(.teal)
            } compactTrailing: {
                Text(context.state.speedText)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "wind")
                    .foregroundStyle(.teal)
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<WindActivityAttributes>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "wind")
                .font(.title2)
                .foregroundStyle(.teal)

            VStack(alignment: .leading, spacing: 2) {
                Text("Strong winds in \(context.attributes.cityName)")
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let direction = context.state.directionText {
                        Text(direction)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let gust = context.state.gustText {
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
                    .foregroundStyle(.teal)
                Text("wind")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
