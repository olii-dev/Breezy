//
//  SurfConditions.swift
//  Breezy
//
//  Surf-specific marine conditions + a transparent rating engine.
//  Surf data is only available from Open-Meteo (WeatherKit exposes no marine data).
//

import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

// MARK: - Surf conditions

struct SurfConditions: Codable, Equatable {
    let waveHeightMeters: Double?
    let wavePeriodSeconds: Double?
    let swellHeightMeters: Double?
    let waveDirectionDegrees: Double?
    let seaTempCelsius: Double?
    let windSpeedMetersPerSecond: Double?
    let windDirectionDegrees: Double?

    /// Computed rating (flat → epic).
    let rating: SurfRating
    /// One/two-word summary, e.g. "Good".
    let ratingLabel: String
    /// Plain-English rationale, e.g. "Chest-high, offshore winds, clean faces."
    let ratingDetail: String
}

// MARK: - Surf rating

enum SurfRating: String, Codable, CaseIterable {
    case flat, poor, fair, good, epic

    var label: String {
        switch self {
        case .flat:  return "Flat"
        case .poor:  return "Poor"
        case .fair:  return "Fair"
        case .good:  return "Good"
        case .epic:  return "Epic"
        }
    }

    /// Stable hex color so widgets (which can't link SwiftUI types from the app
    /// target) can reproduce the rating pill color from the cached payload.
    var hexColor: String {
        switch self {
        case .flat:  return "#9AA4AE" // muted slate
        case .poor:  return "#8D99AE" // cool grey-blue
        case .fair:  return "#E2C044" // amber
        case .good:  return "#5BB381" // green
        case .epic:  return "#3DA9FC" // vivid blue
        }
    }

    #if canImport(SwiftUI)
    /// Color for in-app use.
    var color: Color {
        Color(hex: hexColor)
    }
    #endif
}

// MARK: - Rating engine

/// Pure-logic surf-quality estimator.
///
/// This is a transparent heuristic, not a forecast model. It combines three
/// well-understood surf signals:
///   - **Wave height** → how much to ride.
///   -   **Wave period** → groundswell (>~10s) means organised, powerful waves;
///     short wind waves feel mushy.
///   - **Wind vs. swell direction** → offshore winds (blowing from land toward
///     the incoming swell) hold waves up and keep faces clean; onshore winds
///     chop them up. Cross-shore is in between.
///
/// The result is a guide, not gospel — local bathymetry, tide and fetch matter
/// too. The rationale text only states the facts behind the rating.
enum SurfRatingEngine {

    /// Compute surf conditions + rating from raw marine/wind values.
    /// All inputs are optional; missing values degrade gracefully and the
    /// rating reflects only what is actually known.
    static func conditions(
        waveHeightMeters: Double?,
        wavePeriodSeconds: Double?,
        swellHeightMeters: Double?,
        waveDirectionDegrees: Double?,
        seaTempCelsius: Double?,
        windSpeedMetersPerSecond: Double?,
        windDirectionDegrees: Double?
    ) -> SurfConditions {
        let score = score(
            waveHeightMeters: waveHeightMeters,
            wavePeriodSeconds: wavePeriodSeconds,
            windSpeedMetersPerSecond: windSpeedMetersPerSecond,
            windDirectionDegrees: windDirectionDegrees,
            waveDirectionDegrees: waveDirectionDegrees ?? swellDirectionFallback
        )

        return SurfConditions(
            waveHeightMeters: waveHeightMeters,
            wavePeriodSeconds: wavePeriodSeconds,
            swellHeightMeters: swellHeightMeters,
            waveDirectionDegrees: waveDirectionDegrees,
            seaTempCelsius: seaTempCelsius,
            windSpeedMetersPerSecond: windSpeedMetersPerSecond,
            windDirectionDegrees: windDirectionDegrees,
            rating: score.rating,
            ratingLabel: score.rating.label,
            ratingDetail: score.detail
        )
    }

    // MARK: Internals

    /// When we don't have an explicit swell direction, we have no reliable
    /// offshore/onshore reading; the engine then treats wind influence as neutral.
    private static var swellDirectionFallback: Double? { nil }

    private struct Score {
        let rating: SurfRating
        let detail: String
    }

    private static func score(
        waveHeightMeters: Double?,
        wavePeriodSeconds: Double?,
        windSpeedMetersPerSecond: Double?,
        windDirectionDegrees: Double?,
        waveDirectionDegrees: Double?
    ) -> Score {
        // Nothing to go on at all.
        guard let height = waveHeightMeters, height > 0 else {
            return Score(rating: .flat, detail: flatDetail(period: wavePeriodSeconds))
        }

        // Start from wave height (0–6), then adjust for period and wind.
        var points = heightPoints(height)
        let periodNote = periodAdjust(&points, period: wavePeriodSeconds)
        let windNote = windAdjust(
            &points,
            windSpeed: windSpeedMetersPerSecond,
            windDirection: windDirectionDegrees,
            waveDirection: waveDirectionDegrees
        )

        let rating = ratingFromPoints(points)
        let detail = detailText(
            height: height,
            period: wavePeriodSeconds,
            windNote: windNote,
            periodNote: periodNote
        )
        return Score(rating: rating, detail: detail)
    }

    // Height → base points. ~0.3m is rideable for beginners; ~2m+ is solid.
    private static func heightPoints(_ h: Double) -> Double {
        switch h {
        case ..<0.25:      return 0
        case 0.25..<0.5:   return 1
        case 0.5..<0.9:    return 2.5
        case 0.9..<1.5:    return 4
        case 1.5..<2.5:    return 5
        default:           return 6
        }
    }

    // Period adjusts organisation. >10s = groundswell (good); <6s = wind chop.
    private static func periodAdjust(_ points: inout Double, period: Double?) -> String? {
        guard let period else { return nil }
        switch period {
        case 11...:    points += 2;   return "long-period groundswell"
        case 9..<11:   points += 1;   return "decent swell period"
        case 7..<9:    points += 0;   return nil
        case ..<7:     points -= 1;   return "short, windy swell"
        default:       return nil
        }
    }

    // Wind direction relative to the incoming swell.
    private static func windAdjust(
        _ points: inout Double,
        windSpeed: Double?,
        windDirection: Double?,
        waveDirection: Double?
    ) -> String? {
        guard let windSpeed else { return nil }
        guard let windDirection, let waveDirection else { return nil }

        // Wave direction = where the wave is travelling TO.
        // Offshore wind blows opposite to wave travel (toward the source).
        let relative = angularDifference(windDirection, waveDirection)
        // ~180° → directly offshore (clean). ~0° → onshore (messy).
        switch (relative, windSpeed) {
        case (135...225, _):
            points += 1.5; return "offshore winds, clean"
        case (45..<135, _), (225..<315, _):
            // Cross-shore: light is fine, strong hurts.
            if windSpeed >= 8 { points -= 0.5; return "gusty cross-shore wind" }
            return "light cross-shore wind"
        default:
            // Onshore (0–45° either side).
            switch windSpeed {
            case 8...:   points -= 2;   return "strong onshore winds, choppy"
            case 4..<8:  points -= 1;   return "onshore breeze"
            default:     return "light onshore breeze"
            }
        }
    }

    /// Smallest absolute difference between two compass bearings, in degrees (0–180).
    static func angularDifference(_ a: Double, _ b: Double) -> Double {
        let d = (a - b).truncatingRemainder(dividingBy: 360)
        let abs = Swift.abs(d)
        return abs > 180 ? 360 - abs : abs
    }

    private static func ratingFromPoints(_ p: Double) -> SurfRating {
        switch p {
        case ..<1:    return .flat
        case ..<2.5:  return .poor
        case ..<4.5:  return .fair
        case ..<6.5:  return .good
        default:      return .epic
        }
    }

    // MARK: Detail strings (facts only, no false precision)

    private static func detailText(height: Double, period: Double?, windNote: String?, periodNote: String?) -> String {
        var parts: [String] = [heightDescription(height)]
        if let periodNote { parts.append(periodNote) }
        if let windNote { parts.append(windNote) }
        return parts.joined(separator: ", ") + "."
    }

    /// Surfer-friendly wave-height description (ankle-to-double-overhead scale).
    static func heightDescription(_ m: Double) -> String {
        switch m {
        case ..<0.3:      return "Ankle-slapper waves"
        case 0.3..<0.6:   return "Knee-high waves"
        case 0.6..<0.9:   return "Thigh-to-waist high"
        case 0.9..<1.3:   return "Chest-high waves"
        case 1.3..<1.8:   return "Head-high waves"
        case 1.8..<2.5:   return "Overhead waves"
        default:          return "Double-overhead+"
        }
    }

    private static func flatDetail(period: Double?) -> String {
        if let period, period >= 10 {
            return "Long-period swell, but essentially no wave height."
        }
        return "No rideable waves right now."
    }
}
