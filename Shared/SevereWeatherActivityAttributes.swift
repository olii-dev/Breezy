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
    }

    var cityName: String
}
