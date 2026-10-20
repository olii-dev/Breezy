//
//  AuroraLiveActivityWidget.swift
//  BreezyWidgetExtension
//
//  Live Activity / Dynamic Island — while aurora conditions are plausible
//  tonight. Everything is static per update except the dawn countdown, which
//  renders client-side.
//

import WidgetKit
import SwiftUI
import ActivityKit

struct AuroraLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AuroraActivityAttributes.self) { context in
            lockScreenView(context: context)
                .padding()
                .widgetURL(URL(string: "breezy://alerts"))
                .activityBackgroundTint(LiveActivityTheme.backgroundTint(accent: .purple))
                .activitySystemActionForegroundColor(LiveActivityTheme.foregroundColor())
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Aurora", systemImage: "sparkles")
                            .font(.headline)
                            .foregroundStyle(.purple)
                        Text("Kp \(AuroraKit.formatted(context.state.kp)) of \(AuroraKit.formatted(context.state.requiredKp)) needed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.verdict)
                            .font(.headline)
                            .foregroundStyle(.purple)
                        Text("until \(context.state.dawnDate.formatted(date: .omitted, time: .shortened))")
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
                    HStack(spacing: 12) {
                        if let bz = context.state.bzNanoteslas {
                            Label("\(Int(bz)) nT", systemImage: bz <= -5 ? "arrow.down.circle.fill" : "minus.circle")
                                .font(.caption)
                                .foregroundStyle(bz <= -5 ? .green : .secondary)
                        }
                        if let cloud = context.state.cloudPercent {
                            Label("\(cloud)% cloud", systemImage: "cloud.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let moon = context.state.moonPercent {
                            Label("\(moon)% moon", systemImage: "moonphase.waxing.crescent")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            } compactLeading: {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
            } compactTrailing: {
                Text("Kp\(AuroraKit.formatted(context.state.kp))")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.purple)
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<AuroraActivityAttributes>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.purple)

            VStack(alignment: .leading, spacing: 2) {
                Text("Aurora watch — \(context.attributes.cityName)")
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("Kp \(AuroraKit.formatted(context.state.kp))")
                        .font(.caption.weight(.bold))
                    if let bz = context.state.bzNanoteslas {
                        Text("· Bz \(Int(bz)) nT")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let cloud = context.state.cloudPercent {
                        Text("· \(cloud)% cloud")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(context.state.verdict)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.purple)
                Text("till \(context.state.dawnDate.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
