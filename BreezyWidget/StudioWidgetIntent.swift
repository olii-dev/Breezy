//
//  StudioWidgetIntent.swift
//  BreezyWidgetExtension
//
//  Per-slot configuration for the Widget Studio Home Screen widget: the
//  long-press "Edit Widget" sheet lists the designs saved in the app's
//  Widget Studio, and each widget slot renders the one it picked.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Design storage (widget side)

enum WidgetStudioDesigns {
    private static let suiteName = "group.com.breezy.weather"
    private static let designsKey = "Breezy.CustomWidgetDesigns"
    private static let selectedKey = "Breezy.CustomWidgetSelectedID"

    static var designs: [CustomWidgetConfiguration] {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: designsKey),
              let decoded = try? JSONDecoder().decode([CustomWidgetConfiguration].self, from: data) else {
            return []
        }
        return decoded
    }

    static var selectedID: UUID? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let idString = defaults.string(forKey: selectedKey) else {
            return nil
        }
        return UUID(uuidString: idString)
    }

    static func load(byID id: UUID?) -> CustomWidgetConfiguration? {
        let all = designs
        if let id, let match = all.first(where: { $0.id == id }) {
            return match
        }
        // Fall back to the active design, then the first saved.
        if let selected = selectedID, let match = all.first(where: { $0.id == selected }) {
            return match
        }
        return all.first
    }

    /// Legacy single-config reader, kept so pre-upgrade installs keep rendering.
    static func loadLegacy() -> CustomWidgetConfiguration? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: "Breezy.CustomWidgetConfig") else {
            return nil
        }
        return try? JSONDecoder().decode(CustomWidgetConfiguration.self, from: data)
    }
}

/// Back-compat shim: the main entry view still reads "the active design".
enum WidgetConfigLoader {
    static func load() -> CustomWidgetConfiguration? {
        WidgetStudioDesigns.load(byID: nil) ?? WidgetStudioDesigns.loadLegacy()
    }
}

// MARK: - App Intent configuration

struct WidgetDesignEntity: AppEntity, Hashable, Sendable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Widget Studio Design"
    static let defaultQuery = WidgetDesignQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    init(config: CustomWidgetConfiguration) {
        self.id = config.id
        self.name = config.name
    }
}

struct WidgetDesignQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [WidgetDesignEntity] {
        WidgetStudioDesigns.designs
            .filter { identifiers.contains($0.id) }
            .map(WidgetDesignEntity.init(config:))
    }

    func suggestedEntities() async throws -> [WidgetDesignEntity] {
        WidgetStudioDesigns.designs.map(WidgetDesignEntity.init(config:))
    }

    func defaultResult() async throws -> WidgetDesignEntity? {
        let all = WidgetStudioDesigns.designs
        if let selected = WidgetStudioDesigns.selectedID,
           let match = all.first(where: { $0.id == selected }) {
            return WidgetDesignEntity(config: match)
        }
        return all.first.map(WidgetDesignEntity.init(config:))
    }
}

struct ConfigureStudioWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Widget Studio Design"
    static let description = IntentDescription("Choose which of your Widget Studio designs this widget shows.")

    @Parameter(title: "Design") var design: WidgetDesignEntity?
}

// MARK: - Timeline provider

struct StudioWidgetEntry: TimelineEntry {
    let date: Date
    let weatherEntry: WeatherEntry
    let config: CustomWidgetConfiguration?
}

struct StudioWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StudioWidgetEntry {
        StudioWidgetEntry(date: Date(), weatherEntry: WeatherEntry.mock, config: WidgetStudioDesigns.load(byID: nil))
    }

    func snapshot(for configuration: ConfigureStudioWidgetIntent, in context: Context) async -> StudioWidgetEntry {
        if context.isPreview {
            return StudioWidgetEntry(date: Date(), weatherEntry: WeatherEntry.mock, config: resolve(configuration))
        }
        let base = cachedEntryOrMock()
        return StudioWidgetEntry(date: Date(), weatherEntry: base, config: resolve(configuration))
    }

    func timeline(for configuration: ConfigureStudioWidgetIntent, in context: Context) async -> Timeline<StudioWidgetEntry> {
        let config = resolve(configuration)
        var weatherEntries: [WeatherEntry] = []
        await withCheckedContinuation { continuation in
            Provider().getTimeline(in: context) { timeline in
                weatherEntries = timeline.entries
                continuation.resume()
            }
        }

        let entries = weatherEntries.map { weatherEntry in
            StudioWidgetEntry(date: weatherEntry.date, weatherEntry: weatherEntry, config: config)
        }
        // Mirror the shared provider's refresh cadence; if its timeline carried
        // a policy we lost it in the hand-off, so re-state the 30-minute one.
        return Timeline(entries: entries, policy: .after(Date().addingTimeInterval(30 * 60)))
    }

    private func resolve(_ configuration: ConfigureStudioWidgetIntent) -> CustomWidgetConfiguration? {
        let resolved = WidgetStudioDesigns.load(byID: configuration.design?.id)
            ?? WidgetStudioDesigns.loadLegacy()
        return resolved
    }

    private func cachedEntryOrMock() -> WeatherEntry {
        if let weather = WeatherDataStore.load(for: .selected) {
            return WeatherEntry(date: Date(), weather: weather)
        }
        return WeatherEntry.mock
    }
}

// MARK: - Entry view (same rendering as the static widget, explicit config)

struct StudioWidgetEntryView: View {
    let entry: StudioWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let config = entry.config {
            switch family {
            #if os(iOS)
            case .systemSmall, .systemMedium, .systemLarge:
                CustomWidgetView(entry: entry.weatherEntry, config: config)
            #endif
            default:
                StudioStandardView(entry: entry.weatherEntry)
            }
        } else {
            StudioStandardView(entry: entry.weatherEntry)
        }
    }
}

private struct StudioStandardView: View {
    let entry: WeatherEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        #if os(iOS)
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        #endif
        case .accessoryRectangular:
            AccessoryRectangularView(entry: entry)
        case .accessoryCircular:
            AccessoryCircularView(entry: entry)
        case .accessoryInline:
            AccessoryInlineView(entry: entry)
        default:
            #if os(iOS)
            SmallWidgetView(entry: entry)
            #else
            AccessoryRectangularView(entry: entry)
            #endif
        }
    }
}
