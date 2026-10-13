//
//  HarmonicTideEngine.swift
//  Breezy
//
//  On-device tide prediction from published harmonic constituents
//  (TICON-4, CC BY 4.0, derived from GESLA-4 gauge records — decades of real
//  observations per station). h(t) = Σ f·H·cos(V(t)+u−g) with the standard
//  Doodson equilibrium arguments and main-term nodal corrections.
//

import Foundation

struct TideStation: Codable, Equatable {
    /// Gauge name, e.g. "Port Adelaide Outer Harbor".
    let n: String
    /// ISO country code.
    let c: String
    /// [latitude, longitude].
    let p: [Double]
    /// Constituent name → [amplitude (m), phase lag (degrees)].
    let k: [String: [Double]]
}

enum HarmonicTideEngine {
    /// V = cτ·τ + cs·s + ch·h + cp·p (degrees).
    private static let vcoef: [String: (ct: Double, cs: Double, ch: Double, cp: Double)] = [
        "M2": (2, 0, 0, 0),   "S2": (2, 2, -2, 0),  "N2": (2, -1, 0, 1),
        "K2": (2, 2, 0, 0),   "L2": (2, 1, 0, -1),  "2N2": (2, -2, 0, 2),
        "MU2": (2, -2, 2, 0), "NU2": (2, 0, 0, -1), "T2": (2, 2, -3, 0),
        "EPS2": (2, -2, 0, 2),
        "K1": (1, 1, 0, 0),   "O1": (1, -1, 0, 0),  "Q1": (1, -2, 0, 1),
        "P1": (1, 1, -2, 0),  "J1": (1, 1, 0, -1),  "OO1": (1, -2, 2, 0),
        "RHO1": (1, -2, 0, 1), "SIG1": (1, -3, 0, 1),
        "M4": (4, 0, 0, 0),   "MS4": (4, 2, -2, 0), "MN4": (4, -1, 0, 1),
        "M6": (6, 0, 0, 0),   "2MS6": (6, 2, -2, 0), "M8": (8, 0, 0, 0),
    ]

    // MARK: - Astronomy

    /// Mean longitudes (degrees) at time t — Schureman / almanac rates.
    private static func astronomy(at date: Date) -> (tau: Double, s: Double, h: Double, p: Double, N: Double) {
        let T = date.timeIntervalSince(Date(timeIntervalSince1970: 946_728_000)) / 86_400.0 // days since J2000
        func norm(_ x: Double) -> Double { x.truncatingRemainder(dividingBy: 360) }
        let s = norm(218.3164477 + 13.06499295 * T)
        let h = norm(280.46646 + 0.98564736 * T)
        let p = norm(83.3532465 + 0.11140353 * T)
        let N = norm(125.04452 - 0.05295376 * T)
        let gmst = norm(280.46061837 + 360.98564736629 * T)
        return (norm(gmst - s), s, h, p, N)
    }

    /// Nodal amplitude factor f and phase correction u (degrees), main terms.
    private static func nodal(_ name: String, N degrees: Double) -> (f: Double, u: Double) {
        let N = degrees * .pi / 180
        switch name {
        case "M2", "N2", "2N2", "MU2", "NU2", "EPS2", "L2", "MN4", "M4", "M6", "M8", "2MS6":
            return (1.0004 - 0.0373 * cos(N), -2.14 * sin(N))
        case "K1":
            return (1.0060 + 0.1150 * cos(N) - 0.0088 * cos(2 * N), -0.0517 * sin(N))
        case "O1", "Q1", "RHO1", "SIG1":
            return (1.0089 + 0.1871 * cos(N) - 0.0147 * cos(2 * N), 0.189 * sin(N) - 0.0058 * sin(2 * N))
        case "J1", "OO1":
            return (1.0129 + 0.1676 * cos(N) - 0.0170 * cos(2 * N), -0.206 * sin(N))
        case "K2":
            return (1.0241 + 0.2863 * cos(N) + 0.0083 * cos(2 * N), -17.74 * sin(N) + 0.68 * sin(2 * N))
        default:
            return (1.0, 0.0) // S2, T2, P1, MS4
        }
    }

    /// Predicted sea level (metres, station datum frame) at a single instant.
    static func height(at date: Date, station: TideStation) -> Double {
        let a = astronomy(at: date)
        var total = 0.0
        for (name, pair) in station.k {
            guard pair.count == 2, let (ct, cs, ch, cp) = vcoef[name] else { continue }
            let amp = pair[0]
            let lag = pair[1]
            let argument: Double = ct * a.tau + cs * a.s + ch * a.h + cp * a.p
            let v = norm(argument)
            let fn = nodal(name, N: a.N)
            let radians = (v + fn.u - lag) * Double.pi / 180
            total += fn.f * amp * cos(radians)
        }
        return total
    }

    private static func norm(_ x: Double) -> Double {
        var v = x.truncatingRemainder(dividingBy: 360)
        if v < 0 { v += 360 }
        return v
    }

    // MARK: - Forecast

    /// High/low events for the next `horizon` hours (plus anything under 15
    /// minutes old), sampled at 2-minute resolution with parabolic refinement.
    static func forecast(station: TideStation, now: Date = Date(), horizon: TimeInterval = 72 * 3600) -> TideForecast {
        let start = now.addingTimeInterval(-6 * 3600)
        let step: TimeInterval = 120
        let count = Int((6 * 3600 + horizon) / step)

        var samples: [(date: Date, meters: Double)] = []
        samples.reserveCapacity(count + 1)
        var previous: Double?
        var rising = false
        var currentLevel: Double?

        for i in 0...count {
            let t = start.addingTimeInterval(Double(i) * step)
            let v = height(at: t, station: station)
            samples.append((t, v))
            if t <= now && now < t + step {
                currentLevel = v
                if let prev = previous {
                    rising = v >= prev
                }
            }
            previous = v
        }

        var events: [TideEvent] = []
        for i in 1..<(samples.count - 1) {
            let prev = samples[i - 1].meters
            let mid = samples[i].meters
            let next = samples[i + 1].meters
            if mid == prev && mid == next { continue }

            let isHigh = mid >= prev && mid > next
            let isLow = mid <= prev && mid < next
            guard isHigh || isLow else { continue }

            // Parabolic vertex between the bracketing samples.
            let denominator = prev - 2 * mid + next
            var offsetSteps = 0.0
            if abs(denominator) > 1e-9 {
                offsetSteps = 0.5 * (prev - next) / denominator
                offsetSteps = min(max(offsetSteps, -1), 1)
            }
            let height = mid - 0.25 * (prev - next) * offsetSteps
            let date = samples[i].date.addingTimeInterval(offsetSteps * step)
            events.append(TideEvent(date: date, heightMeters: height, isHigh: isHigh))
        }

        events = events.filter { $0.date >= now.addingTimeInterval(-15 * 60) }

        return TideForecast(currentLevelMeters: currentLevel, isRising: rising, events: events)
    }
}

// MARK: - Station Index

enum TideStationIndex {
    private static let maxDistanceKm: Double = 150

    private static var stations: [TideStation] = {
        guard let url = Bundle.main.url(forResource: "TideStations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([TideStation].self, from: data) else {
            return []
        }
        return decoded
    }()

    /// Nearest gauge to the coordinate, if any within range.
    static func nearestStation(latitude: Double, longitude: Double) -> TideStation? {
        guard !stations.isEmpty else { return nil }
        var best: TideStation?
        var bestDistance = Double.greatestFiniteMagnitude
        for station in stations {
            let d = equirectangularKilometers(fromLat: latitude, lon: longitude, toLat: station.p[0], lon: station.p[1])
            if d < bestDistance {
                bestDistance = d
                best = station
            }
        }
        return bestDistance <= maxDistanceKm ? best : nil
    }

    /// Cheap great-circle-ish distance (equirectangular approximation).
    static func equirectangularKilometers(fromLat lat1: Double, lon lon1: Double, toLat lat2: Double, lon lon2: Double) -> Double {
        let rad = Double.pi / 180
        let meanLat = (lat1 + lat2) / 2 * rad
        let dx = (lon2 - lon1) * rad * cos(meanLat)
        let dy = (lat2 - lat1) * rad
        return 6371 * sqrt(dx * dx + dy * dy)
    }
}
