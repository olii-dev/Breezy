//
//  TideForecastCalculator.swift
//  Breezy
//
//  Turns Open-Meteo's hourly `sea_level_height_msl` series (sea level including
//  tides, MSL-referenced) into high/low tide events. Hourly samples are too
//  coarse to read the turning time directly, so extrema are refined with
//  parabolic interpolation through the bracketing hours.
//

import Foundation

struct TideEvent: Codable, Equatable, Identifiable {
    var id: Date { date }
    let date: Date
    /// Metres relative to mean sea level (can be negative).
    let heightMeters: Double
    let isHigh: Bool
}

struct TideForecast: Equatable {
    /// Current sea level, metres above MSL (nil when no sample covers now).
    var currentLevelMeters: Double?
    /// True while the tide is coming in.
    var isRising: Bool?
    /// Upcoming turning points, soonest first (past-day samples excluded).
    var events: [TideEvent]
}

enum TideForecastCalculator {
    /// Needs hourly (or finer) samples in chronological order; gaps decode as
    /// nil and simply break the series.
    static func forecast(samples: [(date: Date, meters: Double?)], now: Date) -> TideForecast {
        let points = samples.compactMap { sample -> (Date, Double)? in
            guard let meters = sample.meters else { return nil }
            return (sample.date, meters)
        }
        guard points.count >= 3 else {
            return TideForecast(currentLevelMeters: nil, isRising: nil, events: [])
        }

        // Current level + trend from the samples bracketing `now`.
        var currentLevel: Double?
        var rising: Bool?
        if let exact = points.first(where: { $0.0 == now }) {
            currentLevel = exact.1
        } else if let afterIndex = points.firstIndex(where: { $0.0 > now }), afterIndex > 0 {
            let (beforeDate, beforeLevel) = points[afterIndex - 1]
            let (afterDate, afterLevel) = points[afterIndex]
            currentLevel = beforeLevel
            rising = afterLevel >= beforeLevel
            // Linear position between samples for the level itself.
            let span = afterDate.timeIntervalSince(beforeDate)
            if span > 0 {
                let fraction = now.timeIntervalSince(beforeDate) / span
                currentLevel = beforeLevel + (afterLevel - beforeLevel) * min(max(fraction, 0), 1)
            }
            _ = beforeDate
        } else if let last = points.last {
            // Now is after the whole series.
            currentLevel = last.1
        }

        // Turning points: sign change of the first difference.
        var events: [TideEvent] = []
        for i in 1..<(points.count - 1) {
            let (prevDate, prev) = points[i - 1]
            let (midDate, mid) = points[i]
            let (nextDate, next) = points[i + 1]

            let goingUp = mid >= prev
            let keepsGoingUp = next > mid
            let flat = mid == prev && next == mid
            guard !flat else { continue }

            let isHigh = goingUp && !keepsGoingUp
            let isLow = !goingUp && (next >= mid)
            guard isHigh || isLow else { continue }

            // Parabolic refinement: vertex offset in hours from the middle
            // sample, clamped to ±1 sample so a noisy curve can't jump a slot.
            let denominator = prev - 2 * mid + next
            var offsetHours = 0.0
            if abs(denominator) > 1e-9 {
                offsetHours = 0.5 * (prev - next) / denominator
                offsetHours = min(max(offsetHours, -1), 1)
            }

            let height = mid - 0.25 * (prev - next) * offsetHours
            let date = midDate.addingTimeInterval(offsetHours * 3600)
            _ = nextDate
            events.append(TideEvent(date: date, heightMeters: height, isHigh: isHigh))
        }

        // Keep upcoming events only (with a small grace so an event that just
        // passed still reads as "was at 4:02 PM").
        events = events.filter { $0.date >= now.addingTimeInterval(-15 * 60) }

        return TideForecast(currentLevelMeters: currentLevel, isRising: rising, events: events)
    }
}
