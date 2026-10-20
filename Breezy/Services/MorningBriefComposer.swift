//
//  MorningBriefComposer.swift
//  Breezy
//
//  Turns one day of forecast (+ aurora/tides/golden hour context) into a
//  morning-brief notification. The mandate: never a forecast dump — a verdict,
//  in varied voice, from real analysis. Template FAMILIES are picked by a
//  day-seeded shuffle that never repeats yesterday's, and the sentences inside
//  are chosen by the same seed, so two identical forecasts still read
//  differently across the week.
//

import Foundation

enum MorningBriefComposer {

    struct Brief: Equatable {
        let title: String
        let body: String
        /// Which family produced it — persisted so tomorrow differs.
        let familyKey: String
    }

    // MARK: - Analysis inputs (all optional; briefs degrade gracefully)

    struct Context {
        let condition: String
        let highText: String?
        let lowText: String?
        let rainChancePercent: Int?      // daily chance, 0-100
        let nextRainStart: Date?         // minute- or hourly-derived onset
        let nextRainEnd: Date?
        let currentlyRaining: Bool
        let maxHourlyRainChance: Int?    // peak chance in the next 12 h
        let uvPeak: Int?
        let uvPeakTimeText: String?
        let windPeakText: String?
        let humidity: Int?
        let cloudPercent: Int?
        let goldenHourTonight: (start: Date, end: Date)?
        let goldenHourQualityLabel: String?
        let tideNextEvent: String?       // "High tide 3:40 PM"
        let moonIllumination: Int?
        let auroraActive: Bool
        let auroraVerdict: String?
        let city: String

        init(
            condition: String,
            highText: String? = nil, lowText: String? = nil,
            rainChancePercent: Int? = nil,
            nextRainStart: Date? = nil, nextRainEnd: Date? = nil,
            currentlyRaining: Bool = false,
            maxHourlyRainChance: Int? = nil,
            uvPeak: Int? = nil, uvPeakTimeText: String? = nil,
            windPeakText: String? = nil,
            humidity: Int? = nil, cloudPercent: Int? = nil,
            goldenHourTonight: (start: Date, end: Date)? = nil,
            goldenHourQualityLabel: String? = nil,
            tideNextEvent: String? = nil,
            moonIllumination: Int? = nil,
            auroraActive: Bool = false, auroraVerdict: String? = nil,
            city: String
        ) {
            self.condition = condition
            self.highText = highText
            self.lowText = lowText
            self.rainChancePercent = rainChancePercent
            self.nextRainStart = nextRainStart
            self.nextRainEnd = nextRainEnd
            self.currentlyRaining = currentlyRaining
            self.maxHourlyRainChance = maxHourlyRainChance
            self.uvPeak = uvPeak
            self.uvPeakTimeText = uvPeakTimeText
            self.windPeakText = windPeakText
            self.humidity = humidity
            self.cloudPercent = cloudPercent
            self.goldenHourTonight = goldenHourTonight
            self.goldenHourQualityLabel = goldenHourQualityLabel
            self.tideNextEvent = tideNextEvent
            self.moonIllumination = moonIllumination
            self.auroraActive = auroraActive
            self.auroraVerdict = auroraVerdict
            self.city = city
        }

        // MARK: Shape tests (drive family routing)

        var rainNeedsCover: Bool {
            (maxHourlyRainChance ?? 0) >= 70 || (rainChancePercent ?? 0) >= 70
        }

        var rainPossibleLater: Bool {
            !rainNeedsCover && ((maxHourlyRainChance ?? 0) >= 40 || (rainChancePercent ?? 0) >= 40)
        }

        var isHotDay: Bool {
            guard let high = Self.parseDegrees(highText) else { return false }
            return high >= 34
        }

        var isColdDay: Bool {
            guard let high = Self.parseDegrees(highText) else { return false }
            return high <= 5
        }

        private static func parseDegrees(_ text: String?) -> Double? {
            guard let text else { return nil }
            let digits = text.prefix { $0.isNumber || $0 == "-" }
            return Double(digits)
        }
    }

    /// Weather shapes route to families; families own title variants and a
    /// sentence-order shuffle, so the *structure* varies too, not just words.
    private enum Family: String, CaseIterable {
        case umbrella
        case dryDay
        case hotOne
        case coldSnap
        case wildOne       // mixed/variable day
        case goldenMorning // clear + great light

        static func pick(for context: Context) -> Family {
            if context.rainNeedsCover || context.currentlyRaining { return .umbrella }
            if context.isHotDay { return .hotOne }
            if context.isColdDay { return .coldSnap }
            if context.rainPossibleLater { return .wildOne }
            if (context.cloudPercent ?? 100) <= 30 { return .goldenMorning }
            return .dryDay
        }

        /// Day-seeded rotation that avoids yesterday's family.
        static func pick(for context: Context, day: Date, lastUsedKey: String?) -> Family {
            let candidates = matchingFamilies(for: context)
            let seed = Calendar.current.ordinality(of: .day, in: .year, for: day) ?? 0
            let unused = candidates.filter { $0.rawValue != lastUsedKey }
            let pool = unused.isEmpty ? candidates : unused
            return pool[seed % pool.count]
        }

        private static func matchingFamilies(for context: Context) -> [Family] {
            // Shape-defining families stay in play; mild ones all compete.
            if context.rainNeedsCover || context.currentlyRaining { return [.umbrella] }
            if context.isHotDay { return context.rainPossibleLater ? [.hotOne, .wildOne] : [.hotOne, .dryDay] }
            if context.isColdDay { return [.coldSnap, .dryDay] }
            if context.rainPossibleLater { return [.wildOne, .umbrella] }
            return Family.allCases.filter { $0 != .umbrella && $0 != .coldSnap }
        }
    }

    // MARK: - Entry point

    static func compose(context: Context, day: Date = Date(), lastFamilyKey: String?) -> Brief {
        let family = Family.pick(for: context, day: day, lastUsedKey: lastFamilyKey)
        return build(family: family, context: context, day: day)
    }

    // MARK: - Builders

    private static func build(family: Family, context: Context, day: Date) -> Brief {
        let title = title(for: family, context: context, day: day)
        var sentences = coreSentences(for: family, context: context, day: day)
        sentences.append(contentsOf: optionalSentences(for: family, context: context, day: day))

        // Trim to notification length: keep the first two, then fill to ~4.
        var body = sentences.prefix(2).joined(separator: " ")
        if sentences.count > 2 {
            for extra in sentences.dropFirst(2) {
                if (body + " " + extra).count <= 260 { body += " " + extra } else { break }
            }
        }

        return Brief(title: title, body: body, familyKey: family.rawValue)
    }

    private static func title(for family: Family, context: Context, day: Date) -> String {
        let seed = Calendar.current.ordinality(of: .day, in: .year, for: day) ?? 0
        let variants: [String]
        switch family {
        case .umbrella:
            variants = ["Umbrella day", "Wet one today", "Keep the brolly handy"]
        case .dryDay:
            variants = ["Dry and steady", "Clean day ahead", "No rain drama today"]
        case .hotOne:
            variants = ["Hot one today", "Warm day — plan around it", "The heat is the story"]
        case .coldSnap:
            variants = ["Cold one today", "Rug up today", "Winter rules apply"]
        case .wildOne:
            variants = ["Wildcard day", "Day has two acts", "Check back before you head out"]
        case .goldenMorning:
            variants = ["Good day to be outside", "Clear sky day", "Nice one today"]
        }
        return variants[seed % variants.count]
    }

    /// The two load-bearing sentences, family-flavoured.
    private static func coreSentences(for family: Family, context: Context, day: Date) -> [String] {
        var out: [String] = []

        switch family {
        case .umbrella:
            if let start = context.nextRainStart {
                let startText = start.formatted(date: .omitted, time: .shortened)
                if let end = context.nextRainEnd {
                    out.append("Rain moves in around \(startText) and hangs about till \(end.formatted(date: .omitted, time: .shortened)).")
                } else {
                    out.append("Rain moves in around \(startText).")
                }
            } else {
                out.append("Rain is likely through the day — cover whatever you can.")
            }
            if let high = context.highText { out.append("High \(high) — won't dry out much.") }

        case .dryDay:
            out.append("Nothing in the rain story today — do the outdoor thing.")
            if let high = context.highText, let low = context.lowText {
                out.append("\(high) / \(low) across the day.")
            }

        case .hotOne:
            if let high = context.highText {
                out.append("It's heading for \(high), so front-load anything outdoors.")
            }
            if let uv = context.uvPeak, uv >= 8 {
                out.append("UV \(uv) at its worst \(context.uvPeakTimeText ?? "midday") — shade is your friend.")
            }

        case .coldSnap:
            if let low = context.lowText {
                out.append("Starting near \(low), barely climbing from there.")
            }
            if let wind = context.windPeakText {
                out.append("Wind makes it feel sharper — \(wind) at its pushiest.")
            }

        case .wildOne:
            if let start = context.nextRainStart {
                out.append("Dry until about \(start.formatted(date: .omitted, time: .shortened)), then keep an eye out.")
            } else {
                out.append("Rain chances come and go — no all-day washout, no guarantee either.")
            }
            if let high = context.highText, let low = context.lowText {
                out.append("\(high) / \(low) with the weather doing a bit of both.")
            }

        case .goldenMorning:
            out.append("Sky's behaving — good light and no washouts.")
            if let high = context.highText { out.append("High \(high).") }
        }

        return out
    }

    /// Context lines, appended in a day-seeded order so structure varies.
    private static func optionalSentences(for family: Family, context: Context, day: Date) -> [String] {
        var pool: [String] = []

        if family != .umbrella, let start = context.nextRainStart, (context.maxHourlyRainChance ?? 0) >= 30 {
            pool.append("Rain shows up late — around \(start.formatted(date: .omitted, time: .shortened)).")
        }
        if let golden = context.goldenHourTonight, let quality = context.goldenHourQualityLabel {
            pool.append("Golden hour \(golden.start.formatted(date: .omitted, time: .shortened)) — \(quality.lowercased()) light.")
        }
        if let tide = context.tideNextEvent {
            pool.append("\(tide).")
        }
        if let wind = context.windPeakText, family != .coldSnap {
            pool.append("Wind tops out \(wind).")
        }
        if context.auroraActive, let verdict = context.auroraVerdict {
            pool.append("And look up tonight — \(verdict.lowercased()) (\(Int(context.moonIllumination ?? 0))% moon).")
        }
        if context.uvPeak != nil, family != .hotOne, let uv = context.uvPeak, uv >= 8,
           let time = context.uvPeakTimeText {
            pool.append("UV \(uv) \(time) — sunscreen earns its keep.")
        }

        let seed = Calendar.current.ordinality(of: .day, in: .year, for: day) ?? 0
        // Deterministic shuffle with the day seed.
        return pool.enumerated()
            .sorted { (hash($0.element, seed) < hash($1.element, seed)) }
            .map(\.element)
    }

    private static func hash(_ text: String, _ seed: Int) -> Int {
        var h = seed
        for byte in text.utf8 { h = (h &* 31 &+ Int(byte)) & 0x7FFFFFFF }
        return h
    }

    private static func parseDegrees(_ text: String?) -> Double? {
        guard let text else { return nil }
        let digits = text.prefix { $0.isNumber || $0 == "-" }
        return Double(digits)
    }
}
