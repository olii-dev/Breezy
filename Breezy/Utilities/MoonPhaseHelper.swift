//
//  MoonPhaseHelper.swift
//  Breezy
//
//  Moon phase utilities
//

import Foundation

enum MoonPhaseHelper {
    /// Synodic month length in days.
    private static let synodicMonth = 29.530588853
    /// Reference new moon: 2000-01-06 18:14 UTC
    private static let referenceNewMoon = Date(timeIntervalSince1970: 947182800)

    static func phaseName(from illumination: Double) -> String {
        // Illumination alone cannot distinguish waxing vs waning; prefer fromPhaseFraction.
        switch illumination {
        case 0.0..<0.03:
            return "New Moon"
        case 0.03..<0.35:
            return "Waxing Crescent"
        case 0.35..<0.65:
            return illumination < 0.5 ? "First Quarter" : "Full Moon"
        case 0.65..<0.97:
            return "Waxing Gibbous"
        default:
            return "Full Moon"
        }
    }

    /// Phase fraction in [0, 1): 0 = new, 0.25 = first quarter, 0.5 = full, 0.75 = last quarter.
    static func phaseName(fromPhaseFraction fraction: Double) -> String {
        let f = fraction.truncatingRemainder(dividingBy: 1.0)
        let normalized = f < 0 ? f + 1.0 : f
        switch normalized {
        case 0.0..<0.0625, 0.9375..<1.0:
            return "New Moon"
        case 0.0625..<0.1875:
            return "Waxing Crescent"
        case 0.1875..<0.3125:
            return "First Quarter"
        case 0.3125..<0.4375:
            return "Waxing Gibbous"
        case 0.4375..<0.5625:
            return "Full Moon"
        case 0.5625..<0.6875:
            return "Waning Gibbous"
        case 0.6875..<0.8125:
            return "Last Quarter"
        default:
            return "Waning Crescent"
        }
    }

    static func illumination(fromPhaseFraction fraction: Double) -> Double {
        let f = fraction.truncatingRemainder(dividingBy: 1.0)
        let normalized = f < 0 ? f + 1.0 : f
        return (1.0 - cos(normalized * 2.0 * .pi)) / 2.0
    }

    static func phaseFraction(for date: Date) -> Double {
        let days = date.timeIntervalSince(referenceNewMoon) / 86_400.0
        var fraction = (days / synodicMonth).truncatingRemainder(dividingBy: 1.0)
        if fraction < 0 { fraction += 1.0 }
        return fraction
    }

    static func moonPhase(for date: Date) -> MoonPhase {
        let fraction = phaseFraction(for: date)
        let name = phaseName(fromPhaseFraction: fraction)
        return MoonPhase(
            phase: name,
            illumination: illumination(fromPhaseFraction: fraction),
            icon: icon(for: name)
        )
    }

    /// Build a `MoonPhase` from a display name (e.g. mapped from WeatherKit).
    static func moonPhase(named name: String, approximateFraction: Double? = nil, date: Date = Date()) -> MoonPhase {
        let fraction = approximateFraction ?? phaseFraction(for: date)
        return MoonPhase(
            phase: name,
            illumination: illumination(fromPhaseFraction: fraction),
            icon: icon(for: name)
        )
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
            return "moonphase.waxing.crescent"
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
