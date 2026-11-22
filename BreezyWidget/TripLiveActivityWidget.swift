//
//  TripLiveActivityWidget.swift
//  BreezyWidget
//
//  Live Activity / Dynamic Island — while a Go Now drive is active. Weather
//  ahead is the hero; arrival ticks client-side between GPS pushes.
//

import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

struct TripLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            lockScreenView(context: context)
                .padding()
                .activityBackgroundTint(LiveActivityTheme.backgroundTint(accent: .cyan))
                .activitySystemActionForegroundColor(LiveActivityTheme.foregroundColor())
                .widgetURL(URL(string: "breezy://trip"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        if context.state.isPaused == true {
                            Label("Paused", systemImage: "pause.circle.fill")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.orange)
                            Text("tracking off")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(timerInterval: Date()...max(Date().addingTimeInterval(60), context.state.arrival), countsDown: true)
                                .font(.title3.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(accent(for: context.state))
                                .frame(maxWidth: 72, alignment: .leading)
                                .minimumScaleFactor(0.6)
                            Text("until arrival")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.etaText)
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                        Text("arrive")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("→ \(context.state.destinationName)")
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        heroRow(state: context.state, prominent: false)

                        ProgressBarView(
                            progress: context.state.progress,
                            originName: context.attributes.originName,
                            destinationName: context.attributes.destinationName,
                            distanceRemainingText: context.state.distanceRemainingText
                        )

                        controlButtons(state: context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused == true ? "pause.circle.fill" : heroSymbol(for: context.state))
                    .foregroundStyle(context.state.isPaused == true ? .orange : accent(for: context.state))
            } compactTrailing: {
                Text("\(context.state.minutesToArrival)m")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .frame(maxWidth: 40)
            } minimal: {
                Image(systemName: heroSymbol(for: context.state))
                    .foregroundStyle(accent(for: context.state))
            }
        }
    }

    // MARK: - Lock Screen

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<TripActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                // Weather ahead is the hero; the ticking arrival sits beside it.
                heroRow(state: context.state, prominent: true)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    if context.state.isPaused == true {
                        Label("Paused", systemImage: "pause.circle.fill")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.orange)
                        Text("tap Resume")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(timerInterval: Date()...max(Date().addingTimeInterval(60), context.state.arrival), countsDown: true)
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(accent(for: context.state))
                        Text("arrive \(context.state.etaText)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ProgressBarView(
                progress: context.state.progress,
                originName: context.attributes.originName,
                destinationName: context.attributes.destinationName,
                distanceRemainingText: context.state.distanceRemainingText
            )

            controlButtons(state: context.state)
        }
    }

    /// Interactive controls — tappable right on the Lock Screen / Island /
    /// CarPlay dashboard.
    @ViewBuilder
    private func controlButtons(state: TripActivityAttributes.ContentState) -> some View {
        HStack(spacing: 10) {
            if state.isPaused == true {
                Button(intent: ResumeTripIntent()) {
                    Label("Resume", systemImage: "play.circle.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.green)
            } else {
                Button(intent: PauseTripIntent()) {
                    Label("Pause", systemImage: "pause.circle.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }

            Button(intent: EndTripIntent()) {
                Label("End", systemImage: "stop.circle.fill")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }

    @ViewBuilder
    private func heroRow(state: TripActivityAttributes.ContentState, prominent: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: heroSymbol(for: state))
                .font(prominent ? .title2 : .body)
                .foregroundStyle(accent(for: state))

            VStack(alignment: .leading, spacing: 1) {
                if state.isOffRoute {
                    Text("Finding the route…")
                        .font(prominent ? .headline : .caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if let ahead = state.weatherAheadText {
                    Text(ahead)
                        .font(prominent ? .headline : .caption.weight(.semibold))
                        .lineLimit(1)
                    if let minutes = state.weatherAheadMinutes {
                        Text("in ~\(minutes) min")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("\(state.condition) \(state.temperatureText)")
                        .font(prominent ? .headline : .caption.weight(.semibold))
                        .lineLimit(1)
                    if state.isOffline {
                        Text("offline — showing last update")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func heroSymbol(for state: TripActivityAttributes.ContentState) -> String {
        if state.isOffRoute { return "location.slash" }
        return state.weatherAheadSymbolName ?? "car.fill"
    }

    private func accent(for state: TripActivityAttributes.ContentState) -> Color {
        if state.isOffRoute { return .gray }
        guard let symbol = state.weatherAheadSymbolName else { return .cyan }
        switch symbol {
        case "cloud.bolt.rain.fill": return .yellow
        case "snowflake": return .white
        case "eye.slash.fill": return .gray
        case "wind": return .teal
        default: return .cyan
        }
    }
}

/// Origin → destination progress with labels and distance remaining.
private struct ProgressBarView: View {
    let progress: Double
    let originName: String
    let destinationName: String
    let distanceRemainingText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.25))
                        .frame(height: 6)
                    Capsule()
                        .fill(.cyan)
                        .frame(width: max(6, proxy.size.width * CGFloat(min(max(progress, 0), 1))), height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                Text(originName)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let distanceRemainingText {
                    Text(distanceRemainingText)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text(destinationName)
                    .lineLimit(1)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
