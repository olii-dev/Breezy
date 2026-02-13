//
//  MoonPhaseHelper.swift
//  Breezy
//
//  Moon phase utilities
//

import Foundation
import CoreLocation
import Combine

class MoonPhaseHelper {
    static func phaseName(from illumination: Double) -> String {
        // WeatherKit provides illumination as 0.0 to 1.0
        // 0.0 = New Moon, 0.5 = Full Moon
        switch illumination {
        case 0.0..<0.125:
            return "New Moon"
        case 0.125..<0.25:
            return "Waxing Crescent"
        case 0.25..<0.375:
            return "First Quarter"
        case 0.375..<0.5:
            return "Waxing Gibbous"
        case 0.5..<0.625:
            return "Full Moon"
        case 0.625..<0.75:
            return "Waning Gibbous"
        case 0.75..<0.875:
            return "Last Quarter"
        default:
            return "Waning Crescent"
        }
    }
    
    static func icon(for phase: String) -> String {
        switch phase {
        case "New Moon":
            return "moonphase.new.moon"
        case "Waxing Crescent":
            return "moonphase.waxing.crescent"
        case "First Quarter":
            return "moonphase.first.quarter"
        case "Waxing Gibbous":
            return "moonphase.waxing.gibbous"
        case "Full Moon":
            return "moonphase.full.moon"
        case "Waning Gibbous":
            return "moonphase.waning.gibbous"
        case "Last Quarter":
            return "moonphase.last.quarter"
        case "Waning Crescent":
            return "moonphase.waning.crescent"
        default:
            return "moonphase.waxing.crescent" // Safe fallback
        }
    }
    
    static func emoji(for phase: String) -> String {
        switch phase {
        case "New Moon":
            return "🌑"
        case "Waxing Crescent":
            return "🌒"
        case "First Quarter":
            return "🌓"
        case "Waxing Gibbous":
            return "🌔"
        case "Full Moon":
            return "🌕"
        case "Waning Gibbous":
            return "🌖"
        case "Last Quarter":
            return "🌗"
        case "Waning Crescent":
            return "🌘"
        default:
            return "🌙"
        }
    }
}

