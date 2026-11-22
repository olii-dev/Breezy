//
//  WindActivityAttributes.swift
//  Breezy
//
//  Shared attributes for the high-wind Live Activity.
//

import Foundation
import ActivityKit

struct WindActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var speedText: String // e.g. "42 km/h"
        var gustText: String? // e.g. "gusting 61 km/h"
        var directionText: String? // e.g. "from the SW"
        /// When the activity's hard cap lands — ticking countdown material.
        var endsAtDate: Date? = nil
    }

    var cityName: String
}
