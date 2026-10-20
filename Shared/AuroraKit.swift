//
//  AuroraKit.swift
//  Breezy
//
//  Aurora visibility math shared by the app, dashboard card and widgets.
//  Pure functions — no I/O. Data comes from NOAA SWPC via AuroraService.
//
//  Honesty notes baked into the model:
//  - Kp is planetary; high-latitude locations see aurora at much lower Kp
//    than mid-latitudes. The threshold table below is tuned to observed
//    real-world visibility (Tasmania ~Kp 5, Adelaide ~Kp 8) rather than a
//    formal oval model.
//  - Even at qualifying Kp, aurora is never guaranteed: Bz southward and
//    darkness are stacked on top as quality factors, never as promises.
//

import Foundation

enum AuroraKit {

    // MARK: - Visibility threshold by latitude

    /// Kp roughly needed for aurora to be visible from the given geographic
    /// latitude. Piecewise-linear over observed behaviour, both hemispheres —
    /// tables are (poleward distance from equator, Kp) so the same maths
    /// serves both; the southern curve is tuned for the geomagnetic offset
    /// that makes Australia effectively more poleward than its latitude
    /// suggests (Tasmania ~Kp 5, Adelaide ~Kp 8).
    static func requiredKp(latitude: Double) -> Double {
        let north: [(dist: Double, kp: Double)] = [
            (20, 9.5), (40, 9.0), (45, 8.0), (50, 7.0), (55, 5.5), (60, 4.0), (66, 2.5)
        ]
        let south: [(dist: Double, kp: Double)] = [
            (20, 9.5), (30, 9.0), (34, 8.2), (37, 7.5), (40, 6.5), (43, 5.5), (46, 5.0)
        ]

        let table = latitude >= 0 ? north : south
        let dist = abs(latitude)

        if dist <= table[0].dist { return table[0].kp }          // deep tropics
        if dist >= table[table.count - 1].dist { return table[table.count - 1].kp } // deep polar

        for i in 0..<(table.count - 1) {
            let a = table[i], b = table[i + 1]
            if dist >= a.dist && dist <= b.dist {
                let fraction = (dist - a.dist) / (b.dist - a.dist)
                return a.kp + fraction * (b.kp - a.kp)
            }
        }
        return table[table.count - 1].kp
    }

    // MARK: - Assessment

    struct Assessment: Equatable {
        let kp: Double
        let requiredKp: Double
        let isActive: Bool            // kp clears the latitude threshold
        let score: Double             // 0...1, for Smart-Stack/LA relevance
        let verdict: String           // short human verdict
        let detail: String            // one supporting line
    }

    /// Combine Kp, Bz, darkness, cloud and moon into one verdict.
    /// - Parameters:
    ///   - cloudFraction: 0...1 (nil = unknown, neutral)
    ///   - moonIllumination: 0...1 (nil = unknown, neutral)
    ///   - isNight: local sun is down (aurora needs darkness)
    static func assess(
        kp: Double,
        bzNanoteslas: Double?,
        latitude: Double,
        cloudFraction: Double?,
        moonIllumination: Double?,
        isNight: Bool
    ) -> Assessment {
        let required = requiredKp(latitude: latitude)
        let clears = kp >= required && isNight

        var score = max(0, min(1, (kp - (required - 1.5)) / 3.0))
        if let bz = bzNanoteslas {
            // Southward Bz (-ve) couples the solar wind into the magnetosphere.
            if bz <= -5 { score = min(1, score + 0.15) }
            else if bz >= 5 { score = max(0, score - 0.2) }
        }
        if let cloudFraction {
            score *= max(0.15, 1 - cloudFraction * 0.85)
        }
        if let moonIllumination {
            score *= (1 - moonIllumination * 0.35)
        }
        if !isNight { score = 0 }

        let verdict: String
        let detail: String
        if !isNight {
            verdict = "Daylight"
            detail = "Check back after dark"
        } else if clears && score >= 0.55 {
            verdict = "Aurora possible"
            detail = "Kp \(formatted(kp)) clears the \(formatted(required)) needed at your latitude"
        } else if clears {
            verdict = "Marginal"
            detail = cloudHint(cloudFraction, moonIllumination: moonIllumination) ?? "Conditions are borderline"
        } else if kp >= required - 1 {
            verdict = "Building"
            detail = "Kp \(formatted(kp)) — \(formatted(required)) needed from your latitude"
        } else {
            verdict = "Quiet sky"
            detail = "Kp \(formatted(kp)) of \(formatted(required)) needed at your latitude"
        }

        return Assessment(
            kp: kp,
            requiredKp: required,
            isActive: clears && score >= 0.4,
            score: score,
            verdict: verdict,
            detail: detail
        )
    }

    private static func cloudHint(_ cloud: Double?, moonIllumination: Double?) -> String? {
        if let cloud, cloud > 0.6 { return "Clear skies would help — it's \(Int((cloud * 100).rounded()))% clouded" }
        if let moon = moonIllumination, moon > 0.7 { return "The moon is bright tonight (\(Int((moon * 100).rounded()))%)" }
        return nil
    }

    static func formatted(_ value: Double) -> String {
        value >= 9.5 ? "9+" : String(format: "%.0f", value.rounded())
    }

    /// The auroral oval sits poleward of the viewer, so the answer depends on
    /// which pole is yours: south for the southern hemisphere, north for the
    /// northern. (Deep-tropics users never reach an active assessment anyway.)
    static func lookDirection(latitude: Double) -> String {
        latitude < 0
            ? "Face south, away from city lights, and give your eyes 10 minutes."
            : "Face north, away from city lights, and give your eyes 10 minutes."
    }

    // MARK: - Snapshot (app group contract with the widget extension)

    /// Everything the widgets need, precomputed on the phone so the widget
    /// extension never talks to NOAA itself (budget + offline behaviour).
    struct Snapshot: Codable, Equatable {
        var kp: Double?
        var requiredKp: Double?
        var bzNanoteslas: Double?
        var solarWindSpeed: Double?
        var cloudFraction: Double?
        var moonIllumination: Double?
        var isNight: Bool
        var verdict: String
        var detail: String
        var score: Double
        var latitude: Double
        var fetchedAt: Date

        var isActive: Bool { score >= 0.4 }
    }
}

/// App-group persistence for the aurora snapshot, shared by the app and the
/// widget extension (same synced-folder rules as the rest of Shared/).
enum AuroraStore {
    static let key = "Breezy.auroraSnapshot"

    static func save(_ snapshot: AuroraKit.Snapshot) {
        guard let defaults = UserDefaults(suiteName: "group.com.breezy.weather"),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    static func load() -> AuroraKit.Snapshot? {
        guard let defaults = UserDefaults(suiteName: "group.com.breezy.weather"),
              let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(AuroraKit.Snapshot.self, from: data) else { return nil }
        return decoded
    }
}
