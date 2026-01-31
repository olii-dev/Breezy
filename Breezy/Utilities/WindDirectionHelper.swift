//
//  WindDirectionHelper.swift
//  Breezy
//
//  Wind direction utilities
//

import Foundation

struct WindDirectionHelper {
    static func cardinalDirection(from degrees: Double) -> String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                         "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((degrees + 11.25) / 22.5) % 16
        return directions[index]
    }
    
    static func compassAngle(from degrees: Double) -> Double {
        // Convert to compass angle (0 = North, clockwise)
        return degrees
    }
}

