//
//  AlertStateStore.swift
//  Breezy
//
//  Single persisted home for alert bookkeeping (last-sent timestamps, snooze
//  windows, change-detection baselines). Replaces the ~10 ad-hoc UserDefaults
//  keys NotificationManager used to scatter across the defaults domain.
//

import Foundation

struct AlertState: Codable, Equatable {
    // Rain
    var rainSnoozedUntil: Date?
    var lastRainAlertDate: Date?
    var lastRainAlertLocation: String?
    var previousRainPrediction: Bool = false

    // UV
    var lastUVAlertDate: Date?
    var lastUVAlertLocation: String?
    var lastUVAlertIndex: Int?

    // Severe weather
    var lastSevereAlertDate: Date?

    // Wind
    var lastWindAlertDate: Date?

    // Precipitation probability (daily cap)
    var lastPrecipProbabilityAlertDate: Date?

    // Temperature change baseline (previous day, Celsius)
    var lastTemperatureCelsius: Double?
    var lastTemperatureDate: Date?
    var lastTemperatureCity: String?

    // Lenient decoding (decodeIfPresent everywhere) so adding a field later
    // never discards stored alert history.
    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rainSnoozedUntil = try c.decodeIfPresent(Date.self, forKey: .rainSnoozedUntil)
        lastRainAlertDate = try c.decodeIfPresent(Date.self, forKey: .lastRainAlertDate)
        lastRainAlertLocation = try c.decodeIfPresent(String.self, forKey: .lastRainAlertLocation)
        previousRainPrediction = try c.decodeIfPresent(Bool.self, forKey: .previousRainPrediction) ?? false
        lastUVAlertDate = try c.decodeIfPresent(Date.self, forKey: .lastUVAlertDate)
        lastUVAlertLocation = try c.decodeIfPresent(String.self, forKey: .lastUVAlertLocation)
        lastUVAlertIndex = try c.decodeIfPresent(Int.self, forKey: .lastUVAlertIndex)
        lastSevereAlertDate = try c.decodeIfPresent(Date.self, forKey: .lastSevereAlertDate)
        lastWindAlertDate = try c.decodeIfPresent(Date.self, forKey: .lastWindAlertDate)
        lastPrecipProbabilityAlertDate = try c.decodeIfPresent(Date.self, forKey: .lastPrecipProbabilityAlertDate)
        lastTemperatureCelsius = try c.decodeIfPresent(Double.self, forKey: .lastTemperatureCelsius)
        lastTemperatureDate = try c.decodeIfPresent(Date.self, forKey: .lastTemperatureDate)
        lastTemperatureCity = try c.decodeIfPresent(String.self, forKey: .lastTemperatureCity)
    }
}

@MainActor
final class AlertStateStore {
    static let shared = AlertStateStore()

    private(set) var state: AlertState

    private static let storageKey = "Breezy.alertState.v1"

    /// Legacy keys absorbed by the store; read once for migration, then removed.
    private static let legacyKeys: [String] = [
        "Breezy.rainAlertsSnoozedUntil",
        "Breezy.lastRainAlertTime",
        "Breezy.lastRainAlertLocation",
        "Breezy.previousRainPrediction",
        "Breezy.lastUVAlert",
        "Breezy.lastPrecipProbabilityAlert",
        "Breezy.lastTemperature",
        "Breezy.lastTemperatureDate",
        "Breezy.lastTemperatureCity"
    ]

    private struct LegacyUVAlert: Codable {
        let date: Date
        let location: String
        let uvIndex: Int
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(AlertState.self, from: data) {
            state = decoded
            return
        }
        state = Self.migrateFromLegacy(defaults: defaults)
        persist()
        Self.legacyKeys.forEach { defaults.removeObject(forKey: $0) }
    }

    /// Mutate state transactionally; persists on every call.
    func update(_ mutate: (inout AlertState) -> Void) {
        mutate(&state)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private static func migrateFromLegacy(defaults: UserDefaults) -> AlertState {
        var migrated = AlertState()
        migrated.rainSnoozedUntil = defaults.object(forKey: "Breezy.rainAlertsSnoozedUntil") as? Date
        migrated.lastRainAlertDate = defaults.object(forKey: "Breezy.lastRainAlertTime") as? Date
        migrated.lastRainAlertLocation = defaults.string(forKey: "Breezy.lastRainAlertLocation")
        migrated.previousRainPrediction = defaults.bool(forKey: "Breezy.previousRainPrediction")
        if let data = defaults.data(forKey: "Breezy.lastUVAlert"),
           let uv = try? JSONDecoder().decode(LegacyUVAlert.self, from: data) {
            migrated.lastUVAlertDate = uv.date
            migrated.lastUVAlertLocation = uv.location
            migrated.lastUVAlertIndex = uv.uvIndex
        }
        migrated.lastPrecipProbabilityAlertDate = defaults.object(forKey: "Breezy.lastPrecipProbabilityAlert") as? Date
        migrated.lastTemperatureCelsius = defaults.object(forKey: "Breezy.lastTemperature") as? Double
        migrated.lastTemperatureDate = defaults.object(forKey: "Breezy.lastTemperatureDate") as? Date
        migrated.lastTemperatureCity = defaults.string(forKey: "Breezy.lastTemperatureCity")
        return migrated
    }
}
