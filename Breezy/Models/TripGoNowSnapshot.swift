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
