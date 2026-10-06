//
//  TripGoNowSnapshot.swift
//  Breezy
//
//  Shared App Group snapshot for widgets + Go Now live state.
//

import Foundation

struct TripGoNowSnapshot: Codable, Equatable {
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
    // v2 fields — decoded leniently so snapshots from older builds survive.
    var arrival: Date?
    var weatherAheadText: String?
    var weatherAheadMinutes: Int?
    var weatherAheadSymbolName: String?
    var isOffRoute: Bool = false

    init(
        isActive: Bool,
        originName: String,
        destinationName: String,
        etaText: String,
        condition: String,
        temperatureText: String,
        progress: Double,
        nextAlert: String?,
        aheadPlaceLabel: String?,
        distanceRemainingText: String?,
        isOffline: Bool,
        updatedAt: Date,
        arrival: Date? = nil,
        weatherAheadText: String? = nil,
        weatherAheadMinutes: Int? = nil,
        weatherAheadSymbolName: String? = nil,
        isOffRoute: Bool = false
    ) {
        self.isActive = isActive
        self.originName = originName
        self.destinationName = destinationName
        self.etaText = etaText
        self.condition = condition
        self.temperatureText = temperatureText
        self.progress = progress
        self.nextAlert = nextAlert
        self.aheadPlaceLabel = aheadPlaceLabel
        self.distanceRemainingText = distanceRemainingText
        self.isOffline = isOffline
        self.updatedAt = updatedAt
        self.arrival = arrival
        self.weatherAheadText = weatherAheadText
        self.weatherAheadMinutes = weatherAheadMinutes
        self.weatherAheadSymbolName = weatherAheadSymbolName
        self.isOffRoute = isOffRoute
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isActive = try c.decode(Bool.self, forKey: .isActive)
        originName = try c.decode(String.self, forKey: .originName)
        destinationName = try c.decode(String.self, forKey: .destinationName)
        etaText = try c.decode(String.self, forKey: .etaText)
        condition = try c.decode(String.self, forKey: .condition)
        temperatureText = try c.decode(String.self, forKey: .temperatureText)
        progress = try c.decode(Double.self, forKey: .progress)
        nextAlert = try c.decodeIfPresent(String.self, forKey: .nextAlert)
        aheadPlaceLabel = try c.decodeIfPresent(String.self, forKey: .aheadPlaceLabel)
        distanceRemainingText = try c.decodeIfPresent(String.self, forKey: .distanceRemainingText)
        isOffline = try c.decode(Bool.self, forKey: .isOffline)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        arrival = try c.decodeIfPresent(Date.self, forKey: .arrival)
        weatherAheadText = try c.decodeIfPresent(String.self, forKey: .weatherAheadText)
        weatherAheadMinutes = try c.decodeIfPresent(Int.self, forKey: .weatherAheadMinutes)
        weatherAheadSymbolName = try c.decodeIfPresent(String.self, forKey: .weatherAheadSymbolName)
        isOffRoute = try c.decodeIfPresent(Bool.self, forKey: .isOffRoute) ?? false
    }

    static let inactive = TripGoNowSnapshot(
        isActive: false,
        originName: "",
        destinationName: "",
        etaText: "",
        condition: "",
        temperatureText: "",
        progress: 0,
        nextAlert: nil,
        aheadPlaceLabel: nil,
        distanceRemainingText: nil,
        isOffline: false,
        updatedAt: Date.distantPast
    )
}

struct TripWidgetSummary: Codable, Equatable {
    var originName: String
    var destinationName: String
    var departure: Date
    var arrivalETA: Date?
    var arrivalCondition: String?
    var arrivalTemperatureText: String?
    var nextRoughStretch: String?
    var travelTimeText: String?
}
