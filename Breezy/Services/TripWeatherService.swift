//
//  TripWeatherService.swift
//  Breezy
//
//  Batched/cached hourly weather along trip sample points (Open-Meteo).
//  Persists hourly series so offline departure scrub can rematch nearest hour.
//

import Foundation

struct TripHourlyWeatherPoint: Codable, Equatable, Hashable {
    var date: Date
    var weather: TripWeatherSnapshot
}

final class TripWeatherService: @unchecked Sendable {
    static let shared = TripWeatherService()

    /// Round coordinates to ~0.05° (~5 km) for cache coalescing.
    private let coordinateQuantum = 0.05
    private let seriesDefaultsKey = "Breezy.OnTheWay.HourlySeries"
    private let appGroupID = "group.com.breezy.weather"

    private let lock = NSLock()
    /// Point cache: lat,lon,hour → snapshot
    private var cache: [String: TripWeatherSnapshot] = [:]
    /// Location series: "lat,lon" → hourly points
    private var seriesByLocation: [String: [TripHourlyWeatherPoint]] = [:]
    private let session: URLSession

    private init(session: URLSession = .shared) {
        self.session = session
        loadPersistedSeries()
    }

    func clearSessionCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    /// Fills weather on samples for the ETA hour at each point.
    func enrichSamples(
        _ samples: [TripSamplePoint],
        onProgress: (([TripSamplePoint]) -> Void)? = nil
    ) async -> [TripSamplePoint] {
        var working = samples
        let keys = samples.map { pointCacheKey(for: $0) }

        lock.lock()
        let missingIndices = samples.indices.filter { cache[keys[$0]] == nil }
        lock.unlock()

        let batchSize = 6
        var cursor = 0
        while cursor < missingIndices.count {
            let end = min(cursor + batchSize, missingIndices.count)
            let batch = Array(missingIndices[cursor..<end])
            await withTaskGroup(of: (Int, TripWeatherSnapshot?).self) { group in
                for index in batch {
                    let sample = samples[index]
                    group.addTask {
                        let snapshot = try? await self.fetchAndCacheSeries(
                            latitude: sample.latitude,
                            longitude: sample.longitude,
                            at: sample.eta
                        )
                        return (index, snapshot)
                    }
                }
                for await (index, snapshot) in group {
                    if let snapshot {
                        let key = keys[index]
                        self.lock.lock()
                        self.cache[key] = snapshot
                        self.lock.unlock()
                    }
                }
            }
            applyCache(to: &working, keys: keys)
            onProgress?(working)
            cursor = end
        }

        applyCache(to: &working, keys: keys)
        persistSeries()
        return working
    }

    /// Offline rematch: for each sample's current ETA, pick nearest cached hour at that location.
    /// Returns whether every sample found a hour within 90 minutes.
    func rematchSamplesToNearestCachedHour(_ samples: [TripSamplePoint]) -> (samples: [TripSamplePoint], fullyCovered: Bool) {
        lock.lock()
        defer { lock.unlock() }

        var working = samples
        var fullyCovered = true
        for i in working.indices {
            let locKey = locationKey(latitude: working[i].latitude, longitude: working[i].longitude)
            guard let series = seriesByLocation[locKey], !series.isEmpty else {
                fullyCovered = false
                continue
            }
            guard let best = nearest(in: series, to: working[i].eta, maxDelta: 90 * 60) else {
                fullyCovered = false
                continue
            }
            working[i].weather = best.weather
            working[i].riskFlags = Self.riskFlags(for: best.weather)
            let pointKey = String(format: "%@,%d", locKey, Int(working[i].eta.timeIntervalSince1970 / 3600))
            cache[pointKey] = best.weather
        }
        return (working, fullyCovered)
    }

    func riskScore(for samples: [TripSamplePoint]) -> Double {
        samples.reduce(0) { partial, sample in
            guard let weather = sample.weather else { return partial }
            return partial + Self.sampleRiskContribution(weather)
        }
    }

    func arrivalBrief(for samples: [TripSamplePoint], destinationName: String) -> String {
        guard let last = samples.last else {
            return "Plan a route to see your arrival brief."
        }
        let time = Self.timeFormatter.string(from: last.eta)
        guard let weather = last.weather else {
            return "You arrive around \(time)."
        }
        let condition = weather.condition.lowercased()
        let precip = weather.precipitationProbability
        if precip >= 0.5 || condition.contains("rain") || condition.contains("drizzle") || condition.contains("storm") {
            return "You arrive into \(condition) around \(time)."
        }
        if condition.contains("snow") {
            return "You arrive into \(condition) around \(time)."
        }
        return "You arrive in \(destinationName) under \(condition) skies around \(time), \(weather.formattedTemperature)."
    }

    // MARK: - Fetch + series

    private func fetchAndCacheSeries(
        latitude: Double,
        longitude: Double,
        at date: Date
    ) async throws -> TripWeatherSnapshot {
        let roundedLat = roundToQuantum(latitude)
        let roundedLon = roundToQuantum(longitude)
        let locKey = String(format: "%.2f,%.2f", roundedLat, roundedLon)

        // Reuse persisted series if it already covers this ETA well.
        lock.lock()
        if let series = seriesByLocation[locKey],
           let existing = nearest(in: series, to: date, maxDelta: 45 * 60) {
            lock.unlock()
            return existing.weather
        }
        lock.unlock()

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(roundedLat)),
            URLQueryItem(name: "longitude", value: String(roundedLon)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,precipitation,weather_code,visibility,wind_speed_10m,wind_gusts_10m"),
            URLQueryItem(name: "forecast_days", value: "16"),
            URLQueryItem(name: "wind_speed_unit", value: "ms")
        ]
        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(OpenMeteoTripHourlyResponse.self, from: data)
        let timezone = TimeZone(identifier: decoded.timezone) ?? .current
        let series = buildSeries(from: decoded.hourly, timezone: timezone)

        lock.lock()
        seriesByLocation[locKey] = series
        for point in series {
            let hour = Int(point.date.timeIntervalSince1970 / 3600)
            cache["\(locKey),\(hour)"] = point.weather
        }
        lock.unlock()

        guard let best = nearest(in: series, to: date, maxDelta: .greatestFiniteMagnitude) else {
            throw URLError(.cannotDecodeContentData)
        }
        return best.weather
    }

    private func buildSeries(from hourly: OpenMeteoTripHourlyBlock, timezone: TimeZone) -> [TripHourlyWeatherPoint] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        formatter.timeZone = timezone

        var points: [TripHourlyWeatherPoint] = []
        for index in hourly.time.indices {
            guard let hourDate = formatter.date(from: hourly.time[index])
                    ?? Self.fallbackParse(hourly.time[index], timeZone: timezone) else { continue }
            let code = hourly.weatherCode?[safeTrip: index] ?? 0
            let snap = TripWeatherSnapshot(
                temperatureCelsius: hourly.temperature2m?[safeTrip: index] ?? 0,
                condition: TripWMOCode.description(from: code),
                weatherCode: code,
                precipitationProbability: min(1, max(0, (hourly.precipitationProbability?[safeTrip: index] ?? 0) / 100.0)),
                precipitationMillimeters: hourly.precipitation?[safeTrip: index] ?? 0,
                windSpeedMetersPerSecond: hourly.windSpeed10m?[safeTrip: index] ?? 0,
                windGustMetersPerSecond: hourly.windGusts10m?[safeTrip: index],
                visibilityMeters: hourly.visibility?[safeTrip: index]
            )
            points.append(TripHourlyWeatherPoint(date: hourDate, weather: snap))
        }
        return points
    }

    private func nearest(in series: [TripHourlyWeatherPoint], to date: Date, maxDelta: TimeInterval) -> TripHourlyWeatherPoint? {
        var best: TripHourlyWeatherPoint?
        var bestDelta = TimeInterval.greatestFiniteMagnitude
        for point in series {
            let delta = abs(point.date.timeIntervalSince(date))
            if delta < bestDelta {
                bestDelta = delta
                best = point
            }
        }
        guard let best, bestDelta <= maxDelta else { return nil }
        return best
    }

    private func applyCache(to working: inout [TripSamplePoint], keys: [String]) {
        for i in working.indices {
            lock.lock()
            let snap = cache[keys[i]]
            lock.unlock()
            if let snap {
                working[i].weather = snap
                working[i].riskFlags = Self.riskFlags(for: snap)
            }
        }
    }

    // MARK: - Persistence

    private var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    private func loadPersistedSeries() {
        guard let data = defaults.data(forKey: seriesDefaultsKey),
              let decoded = try? JSONDecoder().decode([String: [TripHourlyWeatherPoint]].self, from: data) else {
            return
        }
        lock.lock()
        seriesByLocation = decoded
        for (locKey, series) in decoded {
            for point in series {
                let hour = Int(point.date.timeIntervalSince1970 / 3600)
                cache["\(locKey),\(hour)"] = point.weather
            }
        }
        lock.unlock()
    }

    private func persistSeries() {
        lock.lock()
        let copy = seriesByLocation
        lock.unlock()
        if let encoded = try? JSONEncoder().encode(copy) {
            defaults.set(encoded, forKey: seriesDefaultsKey)
        }
    }

    // MARK: - Risk

    static func riskFlags(for weather: TripWeatherSnapshot) -> [TripRiskFlag] {
        var flags: [TripRiskFlag] = []
        if weather.precipitationProbability >= 0.6 && weather.precipitationMillimeters >= 1.5
            || weather.condition.localizedCaseInsensitiveContains("heavy rain") {
            flags.append(.heavyRain)
        }
        let gust = weather.windGustMetersPerSecond ?? weather.windSpeedMetersPerSecond
        if gust >= 15 || weather.windSpeedMetersPerSecond >= 12 {
            flags.append(.strongWind)
        }
        if let visibility = weather.visibilityMeters, visibility < 1000 {
            flags.append(.lowVisibility)
        }
        if weather.condition.localizedCaseInsensitiveContains("snow")
            || weather.condition.localizedCaseInsensitiveContains("flurries") {
            flags.append(.snow)
        }
        if weather.condition.localizedCaseInsensitiveContains("storm")
            || weather.condition.localizedCaseInsensitiveContains("thunder") {
            flags.append(.storms)
        }
        return flags
    }

    static func sampleRiskContribution(_ weather: TripWeatherSnapshot) -> Double {
        var score = 0.0
        score += weather.precipitationProbability * 2.5
        score += min(weather.precipitationMillimeters, 10) * 0.4
        let gust = weather.windGustMetersPerSecond ?? weather.windSpeedMetersPerSecond
        if gust > 10 { score += (gust - 10) * 0.35 }
        if let visibility = weather.visibilityMeters, visibility < 2000 {
            score += (2000 - visibility) / 500
        }
        if weather.condition.localizedCaseInsensitiveContains("storm") { score += 4 }
        if weather.condition.localizedCaseInsensitiveContains("snow") { score += 2.5 }
        if weather.condition.localizedCaseInsensitiveContains("fog") { score += 1.5 }
        return score
    }

    // MARK: - Keys

    private func pointCacheKey(for sample: TripSamplePoint) -> String {
        let loc = locationKey(latitude: sample.latitude, longitude: sample.longitude)
        let hour = Int(sample.eta.timeIntervalSince1970 / 3600)
        return "\(loc),\(hour)"
    }

    private func locationKey(latitude: Double, longitude: Double) -> String {
        String(format: "%.2f,%.2f", roundToQuantum(latitude), roundToQuantum(longitude))
    }

    private func roundToQuantum(_ value: Double) -> Double {
        (value / coordinateQuantum).rounded() * coordinateQuantum
    }

    private static func fallbackParse(_ string: String, timeZone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = timeZone
        return formatter.date(from: string)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

// MARK: - WMO

enum TripWMOCode {
    static func description(from code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Foggy"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61, 63: return "Rain"
        case 65: return "Heavy Rain"
        case 66, 67: return "Freezing Rain"
        case 71, 73: return "Snow"
        case 75: return "Heavy Snow"
        case 77: return "Flurries"
        case 80, 81: return "Sun Showers"
        case 82: return "Heavy Rain"
        case 85, 86: return "Snow"
        case 95: return "Thunderstorms"
        case 96, 99: return "Strong Storms"
        default: return "Unknown"
        }
    }
}

// MARK: - Open-Meteo DTOs

private struct OpenMeteoTripHourlyResponse: Decodable, Sendable {
    let timezone: String
    let hourly: OpenMeteoTripHourlyBlock
}

private struct OpenMeteoTripHourlyBlock: Decodable, Sendable {
    let time: [String]
    let temperature2m: [Double]?
    let precipitationProbability: [Double]?
    let precipitation: [Double]?
    let weatherCode: [Int]?
    let visibility: [Double]?
    let windSpeed10m: [Double]?
    let windGusts10m: [Double]?

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2m = "temperature_2m"
        case precipitationProbability = "precipitation_probability"
        case precipitation
        case weatherCode = "weather_code"
        case visibility
        case windSpeed10m = "wind_speed_10m"
        case windGusts10m = "wind_gusts_10m"
    }
}

private extension Array {
    subscript(safeTrip index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
