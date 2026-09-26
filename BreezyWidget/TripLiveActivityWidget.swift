//
//  TripLiveActivityWidget.swift
//  BreezyWidget
//
//  Live Activity / Dynamic Island — only while Go Now is active.
//

import WidgetKit
import SwiftUI
import ActivityKit

struct TripLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            lockScreenView(context: context)
                .padding()
                .activityBackgroundTint(.black.opacity(0.4))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.temperatureText)
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                        Text(context.state.condition)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.etaText)
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        Text("\(context.state.minutesToArrival) min")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.destinationName)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: context.state.progress)
                        HStack {
                            if let alert = context.state.nextAlert {
                                Text(alert)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .lineLimit(1)
                            } else if let place = context.state.aheadPlaceLabel {
                                Text("Ahead: \(place)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if context.state.isOffline {
                                Text("Offline")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "car.fill")
            } compactTrailing: {
                if let alert = context.state.nextAlert, alert.contains("min") {
                    Text(shortMinutes(from: alert) ?? context.state.temperatureText)
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                } else {
                    Text(context.state.temperatureText)
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                }
            } minimal: {
                Image(systemName: "car.fill")
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<TripActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("To \(context.state.destinationName)")
                        .font(.headline)
                        .lineLimit(1)
                    Text("ETA \(context.state.etaText) · \(context.state.minutesToArrival) min")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(context.state.temperatureText)
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    Text(context.state.condition)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let alert = context.state.nextAlert {
                Label(alert, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else if let place = context.state.aheadPlaceLabel {
                Text("Weather ahead near \(place)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ProgressView(value: context.state.progress)

            HStack {
                if let remaining = context.state.distanceRemainingText {
                    Text(remaining)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if context.state.isOffline {
                    Text("Offline")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func shortMinutes(from alert: String) -> String? {
        // "Heavy rain in ~18 min" → "~18m"
        guard let range = alert.range(of: #"~?\d+\s*min"#, options: .regularExpression) else { return nil }
        let chunk = String(alert[range]).replacingOccurrences(of: " min", with: "m")
        return chunk
    }
}
