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
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RainActivityAttributes.self) { context in
            lockScreenView(context: context)
                .padding()
                .activityBackgroundTint(.black.opacity(0.4))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Rain", systemImage: "cloud.rain.fill")
                            .font(.headline)
                            .foregroundStyle(.cyan)
                        Text("\(context.state.chancePercent)% chance")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(timerInterval: Date()...max(Date().addingTimeInterval(60), context.state.rainStart), countsDown: true)
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.cyan)
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
                        if let intensity = context.state.intensityText {
                            Text(intensity)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("From \(context.state.rainStart.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "cloud.rain.fill")
                    .foregroundStyle(.cyan)
            } compactTrailing: {
                Text(timerInterval: Date()...max(Date().addingTimeInterval(60), context.state.rainStart), countsDown: true)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "cloud.rain.fill")
                    .foregroundStyle(.cyan)
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<RainActivityAttributes>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "cloud.rain.fill")
                .font(.title2)
                .foregroundStyle(.cyan)

            VStack(alignment: .leading, spacing: 2) {
                Text("Rain approaching \(context.attributes.cityName)")
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(context.state.chancePercent)%")
                        .font(.caption.weight(.semibold))
                    if let intensity = context.state.intensityText {
                        Text(intensity)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("· from \(context.state.rainStart.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(timerInterval: Date()...max(Date().addingTimeInterval(60), context.state.rainStart), countsDown: true)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.cyan)
                Text("until rain")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
