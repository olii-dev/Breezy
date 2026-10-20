//
//  SevereWeatherLiveActivityWidget.swift
//  BreezyWidget
//
//  Live Activity / Dynamic Island — while severe weather is possible.
//

import WidgetKit
import SwiftUI
import ActivityKit

struct SevereWeatherLiveActivityWidget: Widget {
    /// User-picked accent (Live Activity settings) or the family default.
    private var accent: Color { LiveActivityTheme.accent(activity: "severe", fallback: .red) }

    private func on(_ element: String) -> Bool {
        LiveActivityElements.isEnabled(activity: "severe", element: element)
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SevereWeatherActivityAttributes.self) { context in
            lockScreenView(context: context)
                .padding()
                .widgetURL(URL(string: "breezy://alerts"))
                .activityBackgroundTint(LiveActivityTheme.backgroundTint(accent: accent, isSevere: true))
                .activitySystemActionForegroundColor(LiveActivityTheme.foregroundColor())
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.symbolName)
                        .font(.headline)
                        .foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.cityName)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.headline)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } compactLeading: {
                Image(systemName: context.state.symbolName)
                    .foregroundStyle(accent)
            } compactTrailing: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(accent)
            } minimal: {
                Image(systemName: context.state.symbolName)
                    .foregroundStyle(accent)
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<SevereWeatherActivityAttributes>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: context.state.symbolName)
                .font(.title2)
                .foregroundStyle(accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(context.state.headline) — \(context.attributes.cityName)")
                    .font(.headline)
                    .lineLimit(1)
                Text(context.state.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
    }
}
