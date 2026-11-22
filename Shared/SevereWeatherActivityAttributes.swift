//
//  SevereWeatherActivityAttributes.swift
//  Breezy
//
//  Shared attributes for the severe-weather Live Activity.
//

import Foundation
import ActivityKit

struct SevereWeatherActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var headline: String
        var detail: String
        var symbolName: String
        /// When the warning's 12-hour cap lapses — ticking countdown material.
        var expiresAt: Date? = nil
    }

    var cityName: String
}
