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
        /// Arrival instant — lets the widget tick the countdown client-side
        /// between GPS pushes.
        var arrival: Date
        var condition: String
        var temperatureText: String
        var progress: Double
        var nextAlert: String?
        var aheadPlaceLabel: String?
        var distanceRemainingText: String?
        /// Hero weather-ahead line, e.g. "Rain near Gawler".
        var weatherAheadText: String?
        /// Minutes of driving until the hero weather stretch.
        var weatherAheadMinutes: Int?
        var weatherAheadSymbolName: String?
        /// Only true when the device has no network during an active Go Now.
        var isOffline: Bool
        /// GPS can't snap onto the route right now — show "finding the route".
        var isOffRoute: Bool
    }

    var originName: String
    var destinationName: String
}
