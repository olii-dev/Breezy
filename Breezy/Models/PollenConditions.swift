//
//  PollenConditions.swift
//  Breezy
//
//  Pollen concentrations + a transparent allergy-risk rating.
//  Pollen data is only available from Open-Meteo (CAMS European domain);
//  outside Europe every species comes back null and the UI shows an
//  honest "Europe only" state.
//

import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

// MARK: - Pollen conditions

struct PollenConditions: Codable, Equatable {
    let alderPollen: Double?
    let birchPollen: Double?
    let grassPollen: Double?
    let mugwortPollen: Double?
    let olivePollen: Double?
    let ragweedPollen: Double?

    /// Computed overall allergy risk (low → very high).
    let level: PollenLevel
    /// One/two-word summary, e.g. "Moderate".
    let levelLabel: String
    /// Plain-English detail, e.g. "Grass is the main trigger right now."
    let levelDetail: String
    /// Species with the highest concentration relative to its scale, if any.
    let dominantSpeciesName: String?
}

/// One measured species, prepared for display.
struct PollenSpecies: Identifiable, Equatable {
    let name: String
    /// Concentration in grains/m³.
    let value: Double?
    let level: PollenLevel

    var id: String { name }
}

// MARK: - Allergy-risk level

enum PollenLevel: String, Codable, CaseIterable {
    case low, moderate, high, veryHigh

    var label: String {
        switch self {
        case .low:       return "Low"
        case .moderate:  return "Moderate"
        case .high:      return "High"
        case .veryHigh:  return "Very High"
        }
    }

    /// Stable hex color so widgets (which can't link SwiftUI types from the
    /// app target) can reproduce the level pill color from the cached payload.
    var hexColor: String {
        switch self {
        case .low:       return "#5BB381" // green
        case .moderate:  return "#E2C044" // amber
        case .high:      return "#E8833A" // orange
        case .veryHigh:  return "#D64545" // red
        }
    }

    var rank: Int {
        switch self {
        case .low:       return 0
        case .moderate:  return 1
        case .high:      return 2
        case .veryHigh:  return 3
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

/// Pure-logic allergy-risk estimator.
///
/// This is a transparent heuristic, not a measurement. Each species is graded
/// on its own concentration bands (grains/m³), roughly aligned with common
/// European pollen-count guidance — ragweed and mugwort trigger symptoms at
/// much lower counts than grass or birch, so their bands start lower. The
/// overall level is the highest band among species actually present, and the
/// detail names the dominant species. Individual sensitivity varies a lot;
/// this is a guide, not gospel.
enum PollenRatingEngine {

    /// Compute pollen conditions + overall level from raw concentrations.
    /// All inputs are optional; outside the CAMS European domain they will
    /// all be nil and the result reads as "no measurable pollen".
    static func conditions(
        alderPollen: Double?,
        birchPollen: Double?,
        grassPollen: Double?,
        mugwortPollen: Double?,
        olivePollen: Double?,
        ragweedPollen: Double?
    ) -> PollenConditions {
        let species = self.species(
            alderPollen: alderPollen,
            birchPollen: birchPollen,
            grassPollen: grassPollen,
            mugwortPollen: mugwortPollen,
            olivePollen: olivePollen,
            ragweedPollen: ragweedPollen
        )

        let measured = species.compactMap { entry -> (entry: PollenSpecies, value: Double)? in
            guard let value = entry.value else { return nil }
            return (entry, value)
        }

        guard !measured.isEmpty else {
            return PollenConditions(
                alderPollen: alderPollen,
                birchPollen: birchPollen,
                grassPollen: grassPollen,
                mugwortPollen: mugwortPollen,
                olivePollen: olivePollen,
                ragweedPollen: ragweedPollen,
                level: .low,
                levelLabel: PollenLevel.low.label,
                levelDetail: "No measurable pollen right now.",
                dominantSpeciesName: nil
            )
        }

        let overall = measured.map(\.entry.level).max(by: { $0.rank < $1.rank }) ?? .low
        // Dominant = highest concentration relative to the species' own scale,
        // so a modest grass count can outrank a trace of ragweed.
        let dominant = measured.max { lhs, rhs in
            relativeValue(lhs.entry) < relativeValue(rhs.entry)
        }?.entry

        let detail: String
        if overall == .low {
            detail = dominant.map { "Low levels; \($0.name.lowercased()) is the most present." }
                ?? "Pollen levels are low across the board."
        } else {
            detail = "\(dominant?.name ?? "Pollen") is the main trigger right now."
        }

        return PollenConditions(
            alderPollen: alderPollen,
            birchPollen: birchPollen,
            grassPollen: grassPollen,
            mugwortPollen: mugwortPollen,
            olivePollen: olivePollen,
            ragweedPollen: ragweedPollen,
            level: overall,
            levelLabel: overall.label,
            levelDetail: detail,
            dominantSpeciesName: dominant?.name
        )
    }

    /// Species in stable display order (most seasonally relevant first).
    static func species(
        alderPollen: Double?,
        birchPollen: Double?,
        grassPollen: Double?,
        mugwortPollen: Double?,
        olivePollen: Double?,
        ragweedPollen: Double?
    ) -> [PollenSpecies] {
        [
            PollenSpecies(name: "Birch", value: birchPollen, level: level(for: birchPollen, thresholds: birchThresholds)),
            PollenSpecies(name: "Grass", value: grassPollen, level: level(for: grassPollen, thresholds: grassThresholds)),
            PollenSpecies(name: "Alder", value: alderPollen, level: level(for: alderPollen, thresholds: alderThresholds)),
            PollenSpecies(name: "Mugwort", value: mugwortPollen, level: level(for: mugwortPollen, thresholds: mugwortThresholds)),
            PollenSpecies(name: "Olive", value: olivePollen, level: level(for: olivePollen, thresholds: oliveThresholds)),
            PollenSpecies(name: "Ragweed", value: ragweedPollen, level: level(for: ragweedPollen, thresholds: ragweedThresholds))
        ]
    }

    // MARK: Thresholds (grains/m³: moderate, high, veryHigh)

    // Heuristic bands; ragweed/mugwort are far more potent per grain than
    // grass/birch, so their bands sit lower.
    private static let birchThresholds = (moderate: 10.0, high: 30.0, veryHigh: 60.0)
    private static let grassThresholds = (moderate: 10.0, high: 30.0, veryHigh: 50.0)
    private static let alderThresholds = (moderate: 10.0, high: 30.0, veryHigh: 60.0)
    private static let mugwortThresholds = (moderate: 5.0, high: 15.0, veryHigh: 30.0)
    private static let oliveThresholds = (moderate: 5.0, high: 20.0, veryHigh: 40.0)
    private static let ragweedThresholds = (moderate: 5.0, high: 15.0, veryHigh: 30.0)

    private static func level(for value: Double?, thresholds: (moderate: Double, high: Double, veryHigh: Double)) -> PollenLevel {
        guard let value, value > 0 else { return .low }
        switch value {
        case ..<thresholds.moderate:  return .low
        case ..<thresholds.high:      return .moderate
        case ..<thresholds.veryHigh:  return .high
        default:                      return .veryHigh
        }
    }

    /// Where the value sits within the species' own range (0…1+), used to
    /// compare "dominance" across species with very different scales.
    private static func relativeValue(_ species: PollenSpecies) -> Double {
        guard let value = species.value, value > 0 else { return 0 }
        let veryHigh: Double
        switch species.name {
        case "Birch":    veryHigh = birchThresholds.2
        case "Grass":    veryHigh = grassThresholds.2
        case "Alder":    veryHigh = alderThresholds.2
        case "Mugwort":  veryHigh = mugwortThresholds.2
        case "Olive":    veryHigh = oliveThresholds.2
        case "Ragweed":  veryHigh = ragweedThresholds.2
        default:         veryHigh = 50
        }
        return value / veryHigh
    }
}
