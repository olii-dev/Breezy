//
//  UVIndexHelper.swift
//  Breezy
//
//  UV Index utilities and recommendations
//

import Foundation
import CoreLocation
import Combine

class UVIndexHelper {
    static func category(for index: Int) -> String {
        switch index {
        case 0...2:
            return "Low"
        case 3...5:
            return "Moderate"
        case 6...7:
            return "High"
        case 8...10:
            return "Very High"
        default:
            return "Extreme"
        }
    }
    
    static func recommendation(for index: Int) -> String {
        switch index {
        case 0...2:
            return "You can safely stay outside. Minimal protection required."
        case 3...5:
            return "Seek shade during midday hours. Wear sun protection."
        case 6...7:
            return "Protection required. Avoid sun during midday hours."
        case 8...10:
            return "Extra protection required. Avoid sun 10am-4pm."
        default:
            return "Avoid sun exposure. Protection essential."
        }
    }
    
    static func color(for index: Int) -> String {
        switch index {
        case 0...2:
            return "green"
        case 3...5:
            return "yellow"
        case 6...7:
            return "orange"
        case 8...10:
            return "red"
        default:
            return "purple"
        }
    }
}

