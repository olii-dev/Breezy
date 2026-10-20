//
//  StargazingWidget.swift
//  BreezyWidgetExtension
//
//  Aurora / night-sky widget. Reads the snapshot the phone app refreshes
//  alongside every forecast (NOAA Kp + solar wind + local cloud/moon), so the
//  extension never talks to NOAA and renders instantly from cache.
//

import WidgetKit
import SwiftUI

struct StargazingEntry: TimelineEntry {
    let date: Date
    let snapshot: AuroraKit.Snapshot?
    let city: String?
}

struct StargazingProvider: TimelineProvider {
    func placeholder(in context: Context) -> StargazingEntry {
        StargazingEntry(date: Date(), snapshot: nil, city: "Cupertino")
    }

    func getSnapshot(in context: Context, completion: @escaping (StargazingEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StargazingEntry>) -> Void) {
        // Kp moves on ~3-hour steps; the phone refreshes the snapshot more
        // often than that, so half an hour is plenty for this side.
        completion(Timeline(entries: [makeEntry()], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    private func makeEntry() -> StargazingEntry {
        StargazingEntry(date: Date(), snapshot: AuroraStore.load(), city: WeatherDataStore.load()?.city)
    }
}

struct BreezyStargazingWidget: Widget {
    let kind = "BreezyStargazingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StargazingProvider()) { entry in
            StargazingWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Stargazing")
        .description("Aurora odds, cloud and moon for tonight's sky. Updates with the app's forecast.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - Entry view

struct StargazingWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StargazingEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            accessoryRectangular
        case .accessoryCircular:
            accessoryCircular
        case .accessoryInline:
            accessoryInline
        default:
            smallView
        }
    }

    // MARK: Home Screen small — Kp only, per user feedback

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.purple)
                Spacer()
                if let snapshot = entry.snapshot {
                    Text(snapshot.verdict)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(snapshot.isActive ? Color.purple : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            if let snapshot = entry.snapshot, let kp = snapshot.kp {
                Spacer(minLength: 0)
                Text(AuroraKit.formatted(kp))
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(snapshot.isActive ? Color.purple : .primary)
                Text("Kp")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                Spacer()
                Text("Open Breezy to pull tonight's space weather")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Lock Screen rectangular

    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.purple)
                Text("Stargazing")
                    .font(.caption.weight(.bold))
            }
            if let snapshot = entry.snapshot, let kp = snapshot.kp {
                Text("Kp \(AuroraKit.formatted(kp)) — \(snapshot.verdict)")
                    .font(.headline)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(snapshot.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            } else {
                Text("Awaiting space weather")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Lock Screen circular

    private var accessoryCircular: some View {
        VStack(spacing: 0) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(.purple)
            if let snapshot = entry.snapshot, let kp = snapshot.kp {
                Text(AuroraKit.formatted(kp))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                Text("Kp")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("—")
                    .font(.title3.weight(.bold))
            }
        }
    }

    // MARK: Lock Screen inline

    @ViewBuilder
    private var accessoryInline: some View {
        if let snapshot = entry.snapshot, let kp = snapshot.kp {
            Text("✨ Kp \(AuroraKit.formatted(kp)) · \(snapshot.verdict)")
                .font(.caption)
                .lineLimit(1)
        } else {
            Text("✨ Stargazing")
                .font(.caption)
        }
    }
}
