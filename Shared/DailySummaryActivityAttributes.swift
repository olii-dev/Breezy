//
//  DailySummaryActivityAttributes.swift
//  Breezy
//
//  Shared attributes for the daily-forecast summary Live Activity.
//

import Foundation
import ActivityKit

struct DailySummaryActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var conditionText: String
        var highLowText: String // e.g. "H 24° · L 14°"
        var rainChanceText: String? // e.g. "40% rain"
    }

    var cityName: String
    var dayLabel: String // e.g. "Today"
}
