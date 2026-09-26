//
//  RainActivityAttributes.swift
//  Shared between Breezy app and BreezyWidgetExtension.
//
//  Live Activity attributes — shown while rain is approaching the current
//  location. The countdown renders client-side from rainStart, so the app
//  doesn't need to push frequent updates.
//

import Foundation
import ActivityKit

struct RainActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var rainStart: Date
        /// When the rain window is expected to pass, if the forecast shows one.
        var rainEnd: Date?
        var chancePercent: Int
        var intensityText: String?
    }

    var cityName: String
}
