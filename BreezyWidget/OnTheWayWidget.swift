//
//  OnTheWayWidget.swift
//  BreezyWidget
//
//  Home / Lock Screen glance for On the Way — NOT a Live Activity.
//

import WidgetKit
import SwiftUI

#if os(iOS)

private let onTheWayAppGroup = "group.com.breezy.weather"
private let goNowKey = "Breezy.OnTheWay.GoNowSnapshot"
private let summaryKey = "Breezy.OnTheWay.WidgetSummary"

struct OnTheWayGoNowSnapshot: Codable {
    var isActive: Bool
    var originName: String
    var destinationName: String
    var etaText: String
    var condition: String
    var temperatureText: String
    var progress: Double
    var nextAlert: String?
    var aheadPlaceLabel: String?
    var distanceRemainingText: String?
    var isOffline: Bool
    var updatedAt: Date
}

struct OnTheWayWidgetSummary: Codable {
    var originName: String
    var destinationName: String
    var departure: Date
    var arrivalETA: Date?
    var arrivalCondition: String?
    var arrivalTemperatureText: String?
    var nextRoughStretch: String?
    var travelTimeText: String?
}

struct OnTheWayEntry: TimelineEntry {
    let date: Date
    let summary: OnTheWayWidgetSummary?
    let goNow: OnTheWayGoNowSnapshot?
}

struct OnTheWayProvider: TimelineProvider {
    func placeholder(in context: Context) -> OnTheWayEntry {
        OnTheWayEntry(
            date: Date(),
            summary: OnTheWayWidgetSummary(
                originName: "Home",
                destinationName: "Work",
                departure: Date(),
                arrivalETA: Date().addingTimeInterval(3600),
                arrivalCondition: "Rain",
                arrivalTemperatureText: "14°C",
                nextRoughStretch: "Heavy rain near 20 km",
                travelTimeText: "55 min"
            ),
            goNow: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (OnTheWayEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OnTheWayEntry>) -> Void) {
        let entry = loadEntry()
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> OnTheWayEntry {
        let defaults = UserDefaults(suiteName: onTheWayAppGroup)
        var goNow: OnTheWayGoNowSnapshot?
        var summary: OnTheWayWidgetSummary?
        if let data = defaults?.data(forKey: goNowKey),
           let decoded = try? JSONDecoder().decode(OnTheWayGoNowSnapshot.self, from: data),
           decoded.isActive {
            goNow = decoded
        }
        if let data = defaults?.data(forKey: summaryKey) {
            summary = try? JSONDecoder().decode(OnTheWayWidgetSummary.self, from: data)
        }
        return OnTheWayEntry(date: Date(), summary: summary, goNow: goNow)
    }
}

struct OnTheWayWidget: Widget {
    static let kind = "OnTheWayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: OnTheWayProvider()) { entry in
            OnTheWayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("On the Way")
        .description("Your planned drive weather, or live ahead conditions while Go Now is on.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryCircular
        ])
    }
}

struct OnTheWayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: OnTheWayEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
        case .accessoryRectangular:
            rectangularView
        case .accessoryCircular:
            circularView
        default:
            smallView
        }
    }

    @ViewBuilder
    private var smallView: some View {
        if let goNow = entry.goNow {
            VStack(alignment: .leading, spacing: 4) {
                Text(goNow.destinationName)
                    .font(.headline)
                    .lineLimit(1)
                Text(goNow.temperatureText)
                    .font(.title2.weight(.bold))
                Text(goNow.nextAlert ?? goNow.condition)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else if let summary = entry.summary {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.destinationName)
                    .font(.headline)
                    .lineLimit(1)
                Text(summary.arrivalTemperatureText ?? "--°")
                    .font(.title2.weight(.bold))
                Text(summary.nextRoughStretch ?? summary.arrivalCondition ?? "Planned trip")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "road.lanes")
                Text("On the Way")
                    .font(.headline)
                Text("Plan a drive in Breezy")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var mediumView: some View {
        if let goNow = entry.goNow {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Go Now", systemImage: "car.fill")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("ETA \(goNow.etaText)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
                Text("\(goNow.originName) → \(goNow.destinationName)")
                    .font(.headline)
                    .lineLimit(1)
                HStack {
                    Text(goNow.temperatureText)
                        .font(.title.weight(.bold))
                    Text(goNow.condition)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Text(goNow.nextAlert ?? goNow.distanceRemainingText ?? "En route")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ProgressView(value: goNow.progress)
            }
        } else if let summary = entry.summary {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(summary.originName) → \(summary.destinationName)")
                    .font(.headline)
                    .lineLimit(1)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Departs")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(summary.departure, style: .time)
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Arrive")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(summary.arrivalTemperatureText ?? "--°")
                            .font(.title3.weight(.bold))
                    }
                }
                Text(summary.nextRoughStretch ?? summary.arrivalCondition ?? summary.travelTimeText ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        } else {
            HStack(spacing: 12) {
                Image(systemName: "road.lanes")
                    .font(.largeTitle)
                VStack(alignment: .leading, spacing: 4) {
                    Text("On the Way")
                        .font(.headline)
                    Text("Open Breezy to plan weather along your drive.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var rectangularView: some View {
        if let goNow = entry.goNow {
            VStack(alignment: .leading, spacing: 2) {
                Text(goNow.destinationName)
                    .font(.headline)
                    .lineLimit(1)
                Text(goNow.nextAlert ?? "\(goNow.temperatureText) · ETA \(goNow.etaText)")
                    .font(.caption)
                    .lineLimit(1)
            }
        } else if let summary = entry.summary {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.destinationName)
                    .font(.headline)
                    .lineLimit(1)
                Text(summary.nextRoughStretch ?? summary.arrivalTemperatureText ?? "On the Way")
                    .font(.caption)
                    .lineLimit(1)
            }
        } else {
            Text("On the Way")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var circularView: some View {
        if let goNow = entry.goNow {
            Text(goNow.temperatureText)
                .font(.caption.weight(.bold))
        } else if let summary = entry.summary {
            Text(summary.arrivalTemperatureText ?? "🚗")
                .font(.caption.weight(.bold))
                .minimumScaleFactor(0.6)
        } else {
            Image(systemName: "road.lanes")
        }
    }
}

#endif
