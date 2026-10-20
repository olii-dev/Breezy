//
//  AuroraService.swift
//  Breezy
//
//  NOAA SWPC feeds (free, no key, no account), pulled on the same cadence as
//  weather fetches. Feed shapes verified live 2026-10-20:
//  - /json/planetary_k_index_1m.json — objects with kp_index (Int),
//    estimated_kp (Double): the 1-minute WING estimate catches evening
//    escalations the 3-hourly observed Kp misses entirely.
//  - /products/summary/solar-wind-speed.json — [{proton_speed: Int, time_tag}].
//
//  A dedicated Bz feed has no stable summary product right now; the estimate
//  above already folds solar-wind coupling in, so Bz stays nil on the
//  snapshot and every consumer treats it as optional.
//

import Foundation

enum AuroraService {

    private static let kpURL = URL(string: "https://services.swpc.noaa.gov/json/planetary_k_index_1m.json")!
    private static let speedURL = URL(string: "https://services.swpc.noaa.gov/products/summary/solar-wind-speed.json")!

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// Pull both feeds into the freshest snapshot. Partial failure is fine:
    /// wind speed is a nice-to-have, Kp is the core.
    static func fetchSnapshot(latitude: Double) async -> AuroraKit.Snapshot? {
        async let kp = latestKp()
        async let speed = latestWindSpeed()

        guard let kpValue = await kp else { return nil }

        return AuroraKit.Snapshot(
            kp: kpValue,
            requiredKp: nil,
            bzNanoteslas: nil,
            solarWindSpeed: await speed,
            cloudFraction: nil,
            moonIllumination: nil,
            isNight: true,
            verdict: "",
            detail: "",
            score: 0,
            latitude: latitude,
            fetchedAt: Date()
        )
    }

    // MARK: - Parsers

    private struct KpRow: Decodable {
        let kp_index: Int?
        let estimated_kp: Double?
    }

    private static func latestKp() async -> Double? {
        guard let (data, response) = try? await session.data(from: kpURL),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let rows = try? JSONDecoder().decode([KpRow].self, from: data) else { return nil }

        // Walk backwards for the freshest usable estimate; estimated_kp is
        // the model nowcast, kp_index the settled observed value.
        for row in rows.reversed() {
            if let estimated = row.estimated_kp, estimated >= 0, estimated <= 9 { return estimated }
            if let observed = row.kp_index, observed >= 0 { return Double(observed) }
        }
        return nil
    }

    private struct SpeedRow: Decodable {
        let proton_speed: Int?
    }

    private static func latestWindSpeed() async -> Double? {
        guard let (data, response) = try? await session.data(from: speedURL),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let rows = try? JSONDecoder().decode([SpeedRow].self, from: data) else { return nil }

        // The summary product carries one row; be tolerant of a short series.
        return rows.reversed().compactMap(\.proton_speed).first.map(Double.init)
    }
}
