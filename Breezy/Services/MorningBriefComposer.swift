//
//  MorningBriefComposer.swift
//  Breezy
//
//  Turns one day of forecast (+ aurora/tides/golden hour context) into a
//  morning-brief notification. The mandate: never a forecast dump — a verdict,
//  in varied voice, from real analysis.
//
//  Variety model:
//  - TWELVE day-shape families, routed by ordered rules (most specific wins;
//    a storm day is always a storm day, mild overlaps rotate).
//  - 4-5 title variants per family (~50 openings).
//  - Core sentences pick seeded variants where several are truthful.
//  - Optional context lines shuffle by a day seed.
//  - The family rotation never repeats yesterday's when a truthful
//    alternative exists, so identical forecasts still read differently
//    across a week.
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

        var isStormy: Bool {
            let c = condition.lowercased()
            return c.contains("thunder") || c.contains("storm") || c.contains("squall")
        }

        var isSnowy: Bool {
            let c = condition.lowercased()
            return c.contains("snow") || c.contains("blizzard") || c.contains("sleet") || c.contains("flurr")
        }

        var isFoggy: Bool {
            let c = condition.lowercased()
            return c.contains("fog") || c.contains("mist") || c.contains("haze")
        }

        var isFreezing: Bool {
            guard let high = Self.parseDegrees(highText) else { return false }
            return high <= 0
        }

        var isColdDay: Bool {
            guard let high = Self.parseDegrees(highText) else { return false }
            return high > 0 && high <= 5
        }

        var isHotDay: Bool {
            guard let high = Self.parseDegrees(highText) else { return false }
            return high >= 34
        }

        var isMuggy: Bool {
            guard let high = Self.parseDegrees(highText), high >= 26 else { return false }
            return (humidity ?? 0) >= 80
        }

        var isWindy: Bool {
            guard let wind = Self.parseLeadingNumber(windPeakText) else { return false }
            return wind >= 40
        }

        static func parseDegrees(_ text: String?) -> Double? {
            parseLeadingNumber(text)
        }

        static func parseLeadingNumber(_ text: String?) -> Double? {
            guard let text else { return nil }
            let digits = text.prefix { $0.isNumber || $0 == "-" }
            return Double(digits)
        }
    }

    // MARK: - Families

    enum Family: String, CaseIterable {
        case umbrella, stormy, snowy, freezing, coldSnap, foggy, windy, muggy, hotOne, wildOne, goldenMorning, dryDay
    }

    /// Ordered rule match — most specific first. Later rules only add variety
    /// candidates; the first hit is the truthful verdict.
    private static func ruleOrderedFamilies(for c: Context) -> [Family] {
        var matched: [Family] = []
        func add(_ f: Family) { if !matched.contains(f) { matched.append(f) } }

        if c.isStormy { add(.stormy) }
        if c.isSnowy { add(.snowy) }
        if c.currentlyRaining || c.rainNeedsCover { add(.umbrella) }
        if c.isFreezing { add(.freezing) }
        if c.isColdDay { add(.coldSnap) }
        if c.isFoggy { add(.foggy) }
        if c.isWindy { add(.windy) }
        if c.isMuggy { add(.muggy) }
        if c.isHotDay { add(.hotOne) }
        if c.rainPossibleLater { add(.wildOne) }
        // Cloud metric when present; otherwise a "clear" condition counts.
        let clearSky = c.cloudPercent.map { $0 <= 30 }
            ?? c.condition.lowercased().contains("clear")
        if clearSky { add(.goldenMorning) }
        add(.dryDay)
        return matched
    }

    /// Hard families (a genuine hazard or defining sky) never rotate away;
    /// soft overlaps rotate with the day seed, avoiding yesterday's pick.
    private static func pick(for context: Context, day: Date, lastUsedKey: String?) -> Family {
        let ordered = ruleOrderedFamilies(for: context)
        guard let primary = ordered.first else { return .dryDay }

        let isHard = primary == .umbrella || primary == .stormy || primary == .snowy || primary == .freezing
        if isHard || primary.rawValue != lastUsedKey { return primary }

        let softAlternatives = ordered.dropFirst().filter {
            $0 != .umbrella && $0 != .stormy && $0 != .snowy && $0 != .freezing && $0.rawValue != lastUsedKey
        }
        if softAlternatives.isEmpty { return primary }
        let seed = Calendar.current.ordinality(of: .day, in: .year, for: day) ?? 0
        return softAlternatives[seed % softAlternatives.count]
    }

    // MARK: - Titles

    private static let titles: [Family: [String]] = [
        .umbrella: ["Umbrella day", "Wet one today", "Keep the brolly handy", "Rain owns the schedule", "Soaked day"],
        .stormy: ["Stormy one today", "Thunder in the forecast", "Keep an ear on the sky", "Drama in the sky today", "Storm watch"],
        .snowy: ["Snow day", "White one today", "Snow's the story today", "Rug up — snow around", "Slippery one today"],
        .freezing: ["Freezing today", "Ice rules today", "Bitter one today", "Everything's frozen", "Sub-zero day"],
        .coldSnap: ["Cold one today", "Rug up today", "Winter rules apply", "Sharp one today", "Chilly day"],
        .foggy: ["Foggy one today", "Pea-soup morning", "Grey and hazy today", "Misty day", "Low-vis day"],
        .windy: ["Windy one today", "Hold onto your hat", "The wind runs the show", "Blustery day", "Gusty old day"],
        .muggy: ["Muggy one today", "Sticky day ahead", "The air is soup today", "Heavy, warm, sticky", "Tropical-ish today"],
        .hotOne: ["Hot one today", "Warm day — plan around it", "The heat is the story", "Scorcher today", "Sun's got teeth today"],
        .wildOne: ["Wildcard day", "Day has two acts", "Mixed bag today", "The weather's undecided", "Check back before you head out"],
        .goldenMorning: ["Good day to be outside", "Clear-sky day", "Nice one today", "Blue-sky day", "Textbook day"],
        .dryDay: ["Dry and steady", "Clean day ahead", "No rain drama today", "Quiet weather day", "Easy day"]
    ]

    // MARK: - Entry point

    static func compose(context: Context, day: Date = Date(), lastFamilyKey: String?) -> Brief {
        let family = pick(for: context, day: day, lastUsedKey: lastFamilyKey)
        return build(family: family, context: context, day: day)
    }

    // MARK: - Builders

    private static func build(family: Family, context: Context, day: Date) -> Brief {
        let seed = Calendar.current.ordinality(of: .day, in: .year, for: day) ?? 0
        let title = variant(seed, titles[family] ?? ["Today's weather"])

        var sentences = coreSentences(for: family, context: context, seed: seed)
        sentences.append(contentsOf: optionalSentences(for: family, context: context, seed: seed))

        // Trim to notification length: keep the first two, then fill to ~260 chars.
        var body = sentences.prefix(2).joined(separator: " ")
        if sentences.count > 2 {
            for extra in sentences.dropFirst(2) {
                if (body + " " + extra).count <= 260 { body += " " + extra } else { break }
            }
        }

        return Brief(title: title, body: body, familyKey: family.rawValue)
    }

    private static func variant(_ seed: Int, _ options: [String]) -> String {
        options[seed % options.count]
    }

    /// The two load-bearing sentences, family-flavoured, with seeded variants.
    private static func coreSentences(for family: Family, context: Context, seed: Int) -> [String] {
        var out: [String] = []

        switch family {
        case .umbrella:
            if let start = context.nextRainStart {
                let startText = start.formatted(date: .omitted, time: .shortened)
                if let end = context.nextRainEnd {
                    out.append(variant(seed, [
                        "Rain moves in around \(startText) and hangs about till \(end.formatted(date: .omitted, time: .shortened)).",
                        "Showers arrive near \(startText), easing off around \(end.formatted(date: .omitted, time: .shortened)).",
                    ]))
                } else {
                    out.append(variant(seed, [
                        "Rain moves in around \(startText).",
                        "First drops near \(startText) — it doesn't look like stopping.",
                    ]))
                }
            } else {
                out.append(variant(seed, [
                    "Rain is likely through the day — cover whatever you can.",
                    "A wet one: pack the cover, skip the picnic.",
                ]))
            }
            if let high = context.highText {
                out.append(variant(seed, ["High \(high) — won't dry out much.", "Top of \(high), and damp with it."]))
            }

        case .stormy:
            if let start = context.nextRainStart {
                out.append("Storms build around \(start.formatted(date: .omitted, time: .shortened)) — move the outdoor plan before then.")
            } else {
                out.append(variant(seed, [
                    "Thunderstorms are in the picture today — keep anything outdoor flexible.",
                    "Storms on the menu: it's a watch-the-sky kind of day.",
                ]))
            }
            if let wind = context.windPeakText {
                out.append("Gusts hit \(wind) when it lands — bins, trampolines and umbrellas get a say.")
            }

        case .snowy:
            if let low = context.lowText {
                out.append("Snow's around and it's \(low) out there — roads will be slick early.")
            } else {
                out.append("Snow in the forecast — expect slick surfaces and slow traffic.")
            }
            out.append(variant(seed, [
                "Boots, scraper, and a plan B for the commute.",
                "Layers today, and check the car before you go.",
            ]))

        case .freezing:
            if let high = context.highText {
                out.append("It tops out at \(high) — everything wet out there is ice.")
            }
            out.append(variant(seed, [
                "Frost first thing: scrape, layer up, take it easy on footpaths.",
                "Thick socks weather. Give yourself extra time this morning.",
            ]))

        case .coldSnap:
            if let low = context.lowText {
                out.append(variant(seed, [
                    "Starting near \(low), barely climbing from there.",
                    "It's \(low) this morning and in no hurry to warm up.",
                ]))
            }
            if let wind = context.windPeakText {
                out.append("Wind makes it feel sharper — \(wind) at its pushiest.")
            }

        case .foggy:
            out.append(variant(seed, [
                "Thick air out there — give it till mid-morning to burn off.",
                "Visibility is poor early; the fog should lift by late morning.",
            ]))
            out.append(variant(seed, [
                "Drive slow and expect delays on the open road.",
                "Low beams on, big gaps behind the car in front.",
            ]))

        case .windy:
            if let wind = context.windPeakText {
                out.append(variant(seed, [
                    "Gusts to \(wind) — the wind runs the day.",
                    "It blows a gale at \(wind) at peak.",
                ]))
            } else {
                out.append("It's a blustery one from the off.")
            }
            out.append(variant(seed, [
                "Washing, hats and stand-up paddleboards stay inside.",
                "Anything light and outdoorsy is going for a walk without you.",
            ]))

        case .muggy:
            if let high = context.highText, let humidity = context.humidity {
                out.append("\(high) but it'll feel worse — the air's holding \(humidity)% humidity.")
            }
            out.append(variant(seed, [
                "Move anything sweaty to early morning; the afternoon is soup.",
                "Fans on, water bottle full, take it slow out there.",
            ]))

        case .hotOne:
            if let high = context.highText {
                out.append(variant(seed, [
                    "It's heading for \(high), so front-load anything outdoors.",
                    "\(high) at the top — the middle of the day is for shade.",
                ]))
            }
            if let uv = context.uvPeak, uv >= 8 {
                out.append("UV \(uv) at its worst \(context.uvPeakTimeText ?? "midday") — shade is your friend.")
            }

        case .wildOne:
            if let start = context.nextRainStart {
                out.append("Dry until about \(start.formatted(date: .omitted, time: .shortened)), then keep an eye out.")
            } else {
                out.append(variant(seed, [
                    "Rain chances come and go — no all-day washout, no guarantee either.",
                    "The day can't decide: brief showers possible, decent gaps between.",
                ]))
            }
            if let high = context.highText, let low = context.lowText {
                out.append("\(high) / \(low) with the weather doing a bit of both.")
            }

        case .goldenMorning:
            out.append(variant(seed, [
                "Sky's behaving — good light and no washouts.",
                "Clean sky, calm day: the outdoors is open for business.",
            ]))
            if let high = context.highText {
                out.append(variant(seed, ["High \(high).", "Tops out at \(high)."]))
            }

        case .dryDay:
            out.append(variant(seed, [
                "Nothing in the rain story today — do the outdoor thing.",
                "Dry all day: whatever you've been putting off outside, today's fine for it.",
            ]))
            if let high = context.highText, let low = context.lowText {
                out.append("\(high) / \(low) across the day.")
            }
        }

        return out
    }

    /// Context lines, shuffled deterministically by the day seed.
    private static func optionalSentences(for family: Family, context: Context, seed: Int) -> [String] {
        var pool: [String] = []

        if family != .umbrella && family != .stormy, let start = context.nextRainStart,
           (context.maxHourlyRainChance ?? 0) >= 30 {
            pool.append("Rain shows up late — around \(start.formatted(date: .omitted, time: .shortened)).")
        }
        if family != .foggy, let golden = context.goldenHourTonight, let quality = context.goldenHourQualityLabel {
            pool.append("Golden hour \(golden.start.formatted(date: .omitted, time: .shortened)) — \(quality.lowercased()) light.")
        }
        if let tide = context.tideNextEvent {
            pool.append("\(tide).")
        }
        if let wind = context.windPeakText, family != .windy && family != .coldSnap && family != .stormy {
            pool.append("Wind tops out \(wind).")
        }
        if context.auroraActive, let verdict = context.auroraVerdict {
            pool.append("And look up tonight — \(verdict.lowercased()) (\(Int(context.moonIllumination ?? 0))% moon).")
        }
        if context.uvPeak != nil, family != .hotOne && family != .muggy, let uv = context.uvPeak, uv >= 8,
           let time = context.uvPeakTimeText {
            pool.append("UV \(uv) \(time) — sunscreen earns its keep.")
        }
        if let humidity = context.humidity, family != .muggy, humidity >= 85 {
            pool.append("It's a humid one (\(humidity)%) — light layers.")
        }

        // Deterministic shuffle with the day seed.
        return pool.enumerated()
            .sorted { hash($0.element, seed) < hash($1.element, seed) }
            .map(\.element)
    }

    private static func hash(_ text: String, _ seed: Int) -> Int {
        var h = seed
        for byte in text.utf8 { h = (h &* 31 &+ Int(byte)) & 0x7FFFFFFF }
        return h
    }
}
