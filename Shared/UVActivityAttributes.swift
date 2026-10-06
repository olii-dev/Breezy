//
//  UVActivityAttributes.swift
//  Breezy
//
//  Shared attributes for the sun-protection Live Activity.
//

import Foundation
import ActivityKit

struct UVActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var uvIndex: Int
        var categoryText: String
        var dropsBelowText: String? // e.g. "until 4 PM"
    }

    var cityName: String
}
