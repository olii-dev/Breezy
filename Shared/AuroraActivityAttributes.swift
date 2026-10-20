//
//  AuroraActivityAttributes.swift
//  Shared between Breezy app and BreezyWidgetExtension.
//
//  Live Activity attributes — shown while aurora conditions are plausible
//  at the current location tonight. Kp renders as the hero number; the
//  window ends at dawn (delivered as an absolute date so the card can
//  count down client-side between updates).
//

import Foundation
import ActivityKit

struct AuroraActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var kp: Double
        var requiredKp: Double
        /// Positive southward Bz in nT when known (negative = coupling).
        var bzNanoteslas: Double?
        var cloudPercent: Int?
        var moonPercent: Int?
        /// Local dawn — the card ends here.
        var dawnDate: Date
        var verdict: String
    }

    var cityName: String
}
