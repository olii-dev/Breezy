//
//  TripActivityAttributes.swift
//  Shared between Breezy app and BreezyWidgetExtension.
//
//  Live Activity attributes — only used while Go Now is active.
//

import Foundation
import ActivityKit

struct TripActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var destinationName: String
        var etaText: String
        var minutesToArrival: Int
        var condition: String
        var temperatureText: String
        var progress: Double
        var nextAlert: String?
        var aheadPlaceLabel: String?
        var distanceRemainingText: String?
        /// Only true when the device has no network during an active Go Now.
        var isOffline: Bool
    }

    var originName: String
    var destinationName: String
}
