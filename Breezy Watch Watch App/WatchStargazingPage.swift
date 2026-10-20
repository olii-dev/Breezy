//
//  WatchStargazingPage.swift
//  Breezy Watch Watch App
//
//  Aurora + night-sky page. The phone relays NOAA Kp/solar-wind numbers and
//  golden-hour windows through the applicationContext; the watch renders from
//  its app-group cache and never talks to NOAA itself.
//

import SwiftUI

// MARK: - Watch-side cache

enum WatchAuroraStore {
    struct Snapshot: Codable {
        var kp: Double?
        var requiredKp: Double?
        var cloudPercent: Int?
        var moonPercent: Int?
        var verdict: String
        var detail: String
        var goldenEvening: (start: Date, end: Date)?
        var goldenMorning: (start: Date, end: Date)?
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case kp, requiredKp, cloudPercent, moonPercent, verdict, detail, updatedAt
            case goldenEveningStart, goldenEveningEnd
            case goldenMorningStart, goldenMorningEnd
        }

        init(kp: Double?, requiredKp: Double?, cloudPercent: Int?, moonPercent: Int?,
             verdict: String, detail: String,
             goldenEvening: (start: Date, end: Date)?, goldenMorning: (start: Date, end: Date)?,
             updatedAt: Date) {
            self.kp = kp
            self.requiredKp = requiredKp
            self.cloudPercent = cloudPercent
            self.moonPercent = moonPercent
            self.verdict = verdict
            self.detail = detail
            self.goldenEvening = goldenEvening
            self.goldenMorning = goldenMorning
            self.updatedAt = updatedAt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kp = try c.decodeIfPresent(Double.self, forKey: .kp)
            requiredKp = try c.decodeIfPresent(Double.self, forKey: .requiredKp)
            cloudPercent = try c.decodeIfPresent(Int.self, forKey: .cloudPercent)
            moonPercent = try c.decodeIfPresent(Int.self, forKey: .moonPercent)
            verdict = try c.decodeIfPresent(String.self, forKey: .verdict) ?? ""
            detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
            updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
            if let s = try c.decodeIfPresent(Date.self, forKey: .goldenEveningStart),
               let e = try c.decodeIfPresent(Date.self, forKey: .goldenEveningEnd) {
                goldenEvening = (s, e)
            }
            if let s = try c.decodeIfPresent(Date.self, forKey: .goldenMorningStart),
               let e = try c.decodeIfPresent(Date.self, forKey: .goldenMorningEnd) {
                goldenMorning = (s, e)
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(kp, forKey: .kp)
            try c.encodeIfPresent(requiredKp, forKey: .requiredKp)
            try c.encodeIfPresent(cloudPercent, forKey: .cloudPercent)
            try c.encodeIfPresent(moonPercent, forKey: .moonPercent)
            try c.encode(verdict, forKey: .verdict)
            try c.encode(detail, forKey: .detail)
            try c.encode(updatedAt, forKey: .updatedAt)
            try c.encodeIfPresent(goldenEvening?.start, forKey: .goldenEveningStart)
            try c.encodeIfPresent(goldenEvening?.end, forKey: .goldenEveningEnd)
            try c.encodeIfPresent(goldenMorning?.start, forKey: .goldenMorningStart)
            try c.encodeIfPresent(goldenMorning?.end, forKey: .goldenMorningEnd)
        }
    }

    private static let key = "WatchAurora.snapshot"

    static func save(_ snapshot: Snapshot) {
        guard let defaults = UserDefaults(suiteName: WatchAppStorageKey.appGroup),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    static func load() -> Snapshot? {
        guard let defaults = UserDefaults(suiteName: WatchAppStorageKey.appGroup),
              let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
        return decoded
    }

    /// Ingest one applicationContext payload from the phone.
    static func apply(context: [String: Any]) {
        guard context["aurora.kp"] != nil || context["goldenHour.eveningStart"] != nil else { return }

        var snapshot = load() ?? Snapshot(
            kp: nil, requiredKp: nil, cloudPercent: nil, moonPercent: nil,
            verdict: "", detail: "", goldenEvening: nil, goldenMorning: nil,
            updatedAt: .distantPast
        )

        if let kp = context["aurora.kp"] as? Double, kp >= 0 { snapshot.kp = kp }
        if let required = context["aurora.requiredKp"] as? Double, required >= 0 { snapshot.requiredKp = required }
        if let cloud = context["aurora.cloudPercent"] as? Int, cloud >= 0 { snapshot.cloudPercent = cloud }
        if let moon = context["aurora.moonPercent"] as? Int, moon >= 0 { snapshot.moonPercent = moon }
        if let verdict = context["aurora.verdict"] as? String { snapshot.verdict = verdict }
        if let detail = context["aurora.detail"] as? String { snapshot.detail = detail }
        if let updated = context["aurora.updatedAt"] as? TimeInterval { snapshot.updatedAt = Date(timeIntervalSince1970: updated) }

        if let start = context["goldenHour.eveningStart"] as? TimeInterval,
           let end = context["goldenHour.eveningEnd"] as? TimeInterval {
            snapshot.goldenEvening = (Date(timeIntervalSince1970: start), Date(timeIntervalSince1970: end))
        }
        if let start = context["goldenHour.morningStart"] as? TimeInterval,
           let end = context["goldenHour.morningEnd"] as? TimeInterval {
            snapshot.goldenMorning = (Date(timeIntervalSince1970: start), Date(timeIntervalSince1970: end))
        }

        save(snapshot)
    }
}

// MARK: - Page

struct StargazingPageView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var viewModel: WatchWeatherViewModel

    var body: some View {
        let theme = viewModel.currentTheme(isSystemDark: colorScheme == .dark)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let snapshot = WatchAuroraStore.load() {
                    auroraCard(snapshot: snapshot, theme: theme)

                    if let evening = snapshot.goldenEvening {
                        goldenCard(title: "Evening golden hour", window: evening, theme: theme)
                    }
                    if let morning = snapshot.goldenMorning {
                        goldenCard(title: "Morning golden hour", window: morning, theme: theme)
                    }
                } else {
                    Text("Open Breezy on your iPhone to pull tonight's space weather.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func auroraCard(snapshot: WatchAuroraStore.Snapshot, theme: WatchWeatherTheme) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Aurora", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.purple)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let kp = snapshot.kp {
                    Text(AuroraKitLite.formatted(kp))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("Kp")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(snapshot.verdict.isEmpty ? "—" : snapshot.verdict)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.purple)
            }

            if let required = snapshot.requiredKp, snapshot.kp != nil {
                Text("Needs Kp \(AuroraKitLite.formatted(required)) at your latitude")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !snapshot.detail.isEmpty {
                Text(snapshot.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if let cloud = snapshot.cloudPercent {
                    chip(icon: "cloud.fill", text: "\(cloud)%", theme: theme, good: cloud < 35)
                }
                if let moon = snapshot.moonPercent {
                    chip(icon: "moon.fill", text: "\(moon)%", theme: theme, good: moon < 40)
                }
                Spacer()
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.purple.opacity(0.12)))
    }

    private func goldenCard(title: String, window: (start: Date, end: Date), theme: WatchWeatherTheme) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: title.contains("Evening") ? "sunset.fill" : "sunrise.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text("\(time(window.start)) – \(time(window.end))")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(theme.textColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
    }

    private func chip(icon: String, text: String, theme: WatchWeatherTheme, good: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill((good ? Color.green : Color.gray).opacity(0.2)))
        .foregroundStyle(good ? Color.green : theme.textColor.opacity(0.7))
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

/// The watch can't compile Shared/, so it carries the one formatting helper
/// it needs; the real thresholds live in AuroraKit on the phone side.
enum AuroraKitLite {
    static func formatted(_ value: Double) -> String {
        value >= 9.5 ? "9+" : String(format: "%.0f", value.rounded())
    }
}
