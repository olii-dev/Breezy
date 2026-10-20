//
//  UVLiveActivityWidget.swift
//  BreezyWidget
//
//  Live Activity / Dynamic Island — sun protection while UV is high.
//

import WidgetKit
import SwiftUI
import ActivityKit

struct UVLiveActivityWidget: Widget {
    /// User-picked accent (Live Activity settings) or the family default.
    private var accent: Color { LiveActivityTheme.accent(activity: "uv", fallback: .cyan) }

    private func on(_ element: String) -> Bool {
        LiveActivityElements.isEnabled(activity: "uv", element: element)
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: UVActivityAttributes.self) { context in
            lockScreenView(context: context)
                .padding()
                .widgetURL(URL(string: "breezy://alerts"))
                .activityBackgroundTint(LiveActivityTheme.backgroundTint(accent: accent))
                .activitySystemActionForegroundColor(LiveActivityTheme.foregroundColor())
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("UV", systemImage: "sun.max.fill")
                            .font(.headline)
                            .foregroundStyle(.yellow)
                        Text(context.state.categoryText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(context.state.uvIndex)")
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.yellow)
                        Text("UV index")
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
                        Image(systemName: "shield.sun.fill")
                            .foregroundStyle(.yellow)
                        Text("Protect your skin")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if on("drops"), let drops = context.state.dropsBelowText {
                            Text(drops)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.yellow)
            } compactTrailing: {
                Text("\(context.state.uvIndex)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.yellow)
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.yellow)
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<UVActivityAttributes>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "sun.max.fill")
                .font(.title2)
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text("High UV in \(context.attributes.cityName)")
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(context.state.categoryText)
                        .font(.caption.weight(.semibold))
                    if on("drops"), let drops = context.state.dropsBelowText {
                        Text("· \(drops)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(context.state.uvIndex)")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.yellow)
                Text("UV index")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
