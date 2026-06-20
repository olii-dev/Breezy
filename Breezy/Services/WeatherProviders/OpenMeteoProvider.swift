//
//  OpenMeteoProvider.swift
//  Breezy
//
//  Open-Meteo implementation of Breezy's provider protocol.
//

import Foundation

final class OpenMeteoProvider: WeatherProviding {
    static let shared = OpenMeteoProvider()

    let source: WeatherSource = .openMeteo
    let capabilities: WeatherProviderCapabilities = WeatherSource.openMeteo.capabilities

    private let session: URLSession

    private init(session: URLSession = .shared) {
        self.session = session
    }

    func attribution() async -> AppWeatherAttribution? {
        AppWeatherAttribution(
            providerName: source.displayName,
            legalPageURL: source.legalURL,
            summary: source.privacySummary
        )
    }

    func fetchWeather(for location: LocationData, formatting: WeatherFormattingContext) async throws -> WeatherFetchResult {
        async let forecastTask = fetchForecast(latitude: location.latitude, longitude: location.longitude)
        async let airQualityTask = fetchAirQuality(latitude: location.latitude, longitude: location.longitude)
        async let marineTask = fetchMarine(latitude: location.latitude, longitude: location.longitude)

        let response = try await forecastTask
        let airQualityResponse = try? await airQualityTask
        let marineResponse = try? await marineTask
        let timezone = TimeZone(identifier: response.timezone) ?? .current
        let payload = makePayload(
            location: location,
            response: response,
            timezone: timezone,
            airQualityResponse: airQualityResponse,
            marineResponse: marineResponse
        )
        let weather = ProviderWeatherMapper.makeWeatherInfo(from: payload, formatting: formatting)

        return WeatherFetchResult(
            weather: weather,
            attribution: await attribution(),
            conditionCode: payload.current.conditionCode,
            isDaylight: payload.current.isDaylight
        )
    }

    func fetchHistoricalWeather(for location: LocationData, date: Date, formatting: WeatherFormattingContext) async throws -> WeatherInfo {
        let response = try await fetchArchive(latitude: location.latitude, longitude: location.longitude, startDate: date, endDate: date)
        let timezone = TimeZone(identifier: response.timezone) ?? .current
        let daily = makeDaily(from: response.daily, timezone: timezone)
        let hourly = makeHourly(from: response.hourly, timezone: timezone)

        guard let day = daily.first else {
            throw NSError(domain: "Breezy.OpenMeteo", code: 404, userInfo: [NSLocalizedDescriptionKey: "No historical data found"])
        }

        let noonHour = hourly.first { Calendar.current.component(.hour, from: $0.date) == 12 } ?? hourly.first

        return ProviderWeatherMapper.makeHistoricalWeatherInfo(
            location: location,
            timezone: timezone,
            condition: day.condition,
            representativeTemperatureCelsius: day.highTemperatureCelsius,
            highTemperatureCelsius: day.highTemperatureCelsius,
            lowTemperatureCelsius: day.lowTemperatureCelsius,
            hourly: hourly,
            formatting: formatting,
            rainChance: day.precipitationChance,
            rainfallTotalMillimeters: day.precipitationSumMillimeters,
            sunrise: day.sunrise,
            sunset: day.sunset,
            uvIndex: day.uvIndexMax,
            windSpeedMetersPerSecond: day.windSpeedMaxMetersPerSecond,
            windGustMetersPerSecond: hourly.compactMap(\.windGustMetersPerSecond).max(),
            windDirectionDegrees: day.windDirectionDegrees,
            feelsLikeCelsius: nil,
            humidityFraction: noonHour?.humidityFraction,
            pressureHectopascals: noonHour?.pressureHectopascals,
            visibilityMeters: noonHour?.visibilityMeters,
            cloudCoverFraction: noonHour?.cloudCoverFraction
        )
    }

    func fetchHistoricalRange(for location: LocationData, startDate: Date, endDate: Date, formatting: WeatherFormattingContext) async throws -> [HistoricalDataPoint] {
        let response = try await fetchArchive(latitude: location.latitude, longitude: location.longitude, startDate: startDate, endDate: endDate)
        let timezone = TimeZone(identifier: response.timezone) ?? .current
        let daily = makeDaily(from: response.daily, timezone: timezone)
        return ProviderWeatherMapper.makeHistoricalRange(from: daily)
    }

    private func fetchForecast(latitude: Double, longitude: Double) async throws -> OpenMeteoForecastResponse {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,pressure_msl,cloud_cover,wind_speed_10m,wind_direction_10m,wind_gusts_10m,visibility"),
            URLQueryItem(name: "hourly", value: "temperature_2m,relative_humidity_2m,apparent_temperature,precipitation_probability,precipitation,weather_code,pressure_msl,cloud_cover,visibility,wind_speed_10m,wind_direction_10m,wind_gusts_10m,uv_index"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max,precipitation_sum,wind_speed_10m_max,wind_direction_10m_dominant,uv_index_max"),
            URLQueryItem(name: "forecast_days", value: "10")
        ]

        guard let url = components?.url else {
            throw NSError(domain: "Breezy.OpenMeteo", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid forecast URL"])
        }

        let (data, response) = try await performRequest(url)
        try validate(response: response)
        let decoder = JSONDecoder()
        return try decoder.decode(OpenMeteoForecastResponse.self, from: data)
    }

    private func fetchAirQuality(latitude: Double, longitude: Double) async throws -> OpenMeteoAirQualityResponse {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "current", value: "us_aqi,pm10,pm2_5,carbon_monoxide,nitrogen_dioxide,sulphur_dioxide,ozone")
        ]

        guard let url = components?.url else {
            throw NSError(domain: "Breezy.OpenMeteo", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid air quality URL"])
        }

        let (data, response) = try await performRequest(url)
        try validate(response: response)
        return try JSONDecoder().decode(OpenMeteoAirQualityResponse.self, from: data)
    }

    private func fetchMarine(latitude: Double, longitude: Double) async throws -> OpenMeteoMarineResponse {
        var components = URLComponents(string: "https://marine-api.open-meteo.com/v1/marine")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "current", value: "wave_height,wave_direction,wave_period,wind_wave_height,swell_wave_height,sea_surface_temperature,ocean_current_velocity,ocean_current_direction")
        ]

        guard let url = components?.url else {
            throw NSError(domain: "Breezy.OpenMeteo", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid marine URL"])
        }

        let (data, response) = try await performRequest(url)
        try validate(response: response)
        return try JSONDecoder().decode(OpenMeteoMarineResponse.self, from: data)
    }

    private func fetchArchive(latitude: Double, longitude: Double, startDate: Date, endDate: Date) async throws -> OpenMeteoArchiveResponse {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        var components = URLComponents(string: "https://archive-api.open-meteo.com/v1/archive")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "start_date", value: formatter.string(from: startDate)),
            URLQueryItem(name: "end_date", value: formatter.string(from: endDate)),
            // The historical archive API does not expose the exact same variable set
            // as the live forecast API. Keep this list limited to archive-supported
            // fields so Time Machine requests do not get rejected with HTTP 400.
            URLQueryItem(name: "hourly", value: "temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,pressure_msl,cloud_cover,visibility,wind_speed_10m,wind_direction_10m,wind_gusts_10m"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_sum,wind_speed_10m_max,wind_direction_10m_dominant")
        ]

        guard let url = components?.url else {
            throw NSError(domain: "Breezy.OpenMeteo", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid archive URL"])
        }

        let (data, response) = try await performRequest(url)
        try validate(response: response)
        let decoder = JSONDecoder()
        return try decoder.decode(OpenMeteoArchiveResponse.self, from: data)
    }

    private func performRequest(_ url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        return try await session.data(for: request)
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "Breezy.OpenMeteo", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Open-Meteo returned an error"])
        }
    }

    private func makePayload(
        location: LocationData,
        response: OpenMeteoForecastResponse,
        timezone: TimeZone,
        airQualityResponse: OpenMeteoAirQualityResponse?,
        marineResponse: OpenMeteoMarineResponse?
    ) -> ProviderWeatherPayload {
        let hourly = makeHourly(from: response.hourly, timezone: timezone)
        let daily = makeDaily(from: response.daily, timezone: timezone)

        let currentDate = parseCurrentDate(response.current.time, timezone: timezone)
        let currentCondition = OpenMeteoWeatherCodeConverter.description(from: response.current.weatherCode)
        let current = ProviderCurrentWeather(
            temperatureCelsius: response.current.temperature2M,
            feelsLikeCelsius: response.current.apparentTemperature,
            condition: currentCondition,
            conditionCode: String(response.current.weatherCode),
            isDaylight: response.current.isDay == 1,
            uvIndex: hourly.first(where: { Calendar.current.isDate($0.date, equalTo: currentDate, toGranularity: .hour) })?.uvIndex ?? 0,
            pressureHectopascals: response.current.pressureMSL,
            visibilityMeters: response.current.visibility,
            dewPointCelsius: nil,
            humidityFraction: response.current.relativeHumidity2M.map { $0 / 100.0 },
            windDirectionDegrees: response.current.windDirection10M,
            windSpeedMetersPerSecond: response.current.windSpeed10M / 3.6,
            windGustMetersPerSecond: response.current.windGusts10M.map { $0 / 3.6 },
            precipitationChance: daily.first?.precipitationChance,
            precipitationIntensityMillimetersPerHour: response.current.precipitation,
            cloudCoverFraction: response.current.cloudCover.map { $0 / 100.0 },
            airQuality: makeAirQuality(from: airQualityResponse?.current),
            marine: makeMarine(from: marineResponse?.current)
        )

        return ProviderWeatherPayload(
            location: location,
            timezone: timezone,
            current: current,
            hourly: hourly,
            daily: daily,
            minuteForecast: []
        )
    }

    private func makeHourly(from source: OpenMeteoHourlyBlock, timezone: TimeZone) -> [ProviderHourlyWeather] {
        let times = parseHourlyDates(source.time, timezone: timezone)

        return times.enumerated().map { index, date in
            let code = source.weatherCode?[safe: index] ?? 0
            return ProviderHourlyWeather(
                date: date,
                temperatureCelsius: source.temperature2M?[safe: index] ?? 0,
                condition: OpenMeteoWeatherCodeConverter.description(from: code),
                conditionCode: String(code),
                precipitationChance: value(at: index, in: source.precipitationProbability).map { $0 / 100.0 },
                precipitationAmountMillimeters: value(at: index, in: source.precipitation),
                windSpeedMetersPerSecond: value(at: index, in: source.windSpeed10M).map { $0 / 3.6 },
                windGustMetersPerSecond: value(at: index, in: source.windGusts10M).map { $0 / 3.6 },
                windDirectionDegrees: value(at: index, in: source.windDirection10M),
                uvIndex: value(at: index, in: source.uvIndex).map { Int(round($0)) },
                humidityFraction: source.relativeHumidity2M?[safe: index].map { $0 / 100.0 },
                pressureHectopascals: value(at: index, in: source.pressureMSL),
                visibilityMeters: value(at: index, in: source.visibility),
                cloudCoverFraction: value(at: index, in: source.cloudCover).map { $0 / 100.0 }
            )
        }
    }

    private func makeDaily(from source: OpenMeteoDailyBlock, timezone: TimeZone) -> [ProviderDailyWeather] {
        let dates = parseDailyDates(source.time, timezone: timezone)
        let sunriseDates = parseHourlyDates(source.sunrise ?? [], timezone: timezone)
        let sunsetDates = parseHourlyDates(source.sunset ?? [], timezone: timezone)

        return dates.enumerated().map { index, date in
            let code = source.weatherCode?[safe: index] ?? 0
            return ProviderDailyWeather(
                date: date,
                highTemperatureCelsius: source.temperature2MMax?[safe: index] ?? 0,
                lowTemperatureCelsius: source.temperature2MMin?[safe: index] ?? 0,
                condition: OpenMeteoWeatherCodeConverter.description(from: code),
                conditionCode: String(code),
                precipitationChance: value(at: index, in: source.precipitationProbabilityMax).map { $0 / 100.0 },
                precipitationSumMillimeters: value(at: index, in: source.precipitationSum),
                windSpeedMaxMetersPerSecond: value(at: index, in: source.windSpeed10MMax).map { $0 / 3.6 },
                windDirectionDegrees: value(at: index, in: source.windDirection10MDominant),
                uvIndexMax: value(at: index, in: source.uvIndexMax).map { Int(round($0)) },
                sunrise: sunriseDates[safe: index],
                sunset: sunsetDates[safe: index],
                moonPhase: nil,
                moonrise: nil,
                moonset: nil
            )
        }
    }

    private func parseHourlyDates(_ values: [String], timezone: TimeZone) -> [Date] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = timezone

        return values.compactMap { formatter.date(from: $0) }
    }

    private func parseCurrentDate(_ value: String, timezone: TimeZone) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = timezone
        return formatter.date(from: value) ?? Date()
    }

    private func parseDailyDates(_ values: [String], timezone: TimeZone) -> [Date] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = timezone

        return values.compactMap { formatter.date(from: $0) }
    }

    private func makeAirQuality(from current: OpenMeteoAirQualityCurrentBlock?) -> AirQuality? {
        guard let current else { return nil }
        let aqi = current.usAQI.map { Int(round($0)) }
        let dominantPollutant = dominantPollutant(from: current)
        guard aqi != nil || dominantPollutant != nil else { return nil }
        return AirQuality(
            aqi: aqi,
            category: aqi.map { AirQualityHelper.category(for: $0) },
            dominantPollutant: dominantPollutant
        )
    }

    private func dominantPollutant(from current: OpenMeteoAirQualityCurrentBlock) -> String? {
        let pollutantPairs: [(String, Double?)] = [
            ("PM2.5", current.pm25),
            ("PM10", current.pm10),
            ("Ozone", current.ozone),
            ("NO₂", current.nitrogenDioxide),
            ("SO₂", current.sulphurDioxide),
            ("CO", current.carbonMonoxide)
        ]

        return pollutantPairs
            .compactMap { name, value in value.map { (name, $0) } }
            .max(by: { $0.1 < $1.1 })?
            .0
    }

    private func makeMarine(from current: OpenMeteoMarineCurrentBlock?) -> ProviderMarineConditions? {
        guard let current else { return nil }
        return ProviderMarineConditions(
            waveHeightMeters: current.waveHeight,
            waveDirectionDegrees: current.waveDirection,
            wavePeriodSeconds: current.wavePeriod,
            swellHeightMeters: current.swellWaveHeight ?? current.windWaveHeight,
            seaSurfaceTemperatureCelsius: current.seaSurfaceTemperature,
            currentSpeedMetersPerSecond: current.oceanCurrentVelocity,
            currentDirectionDegrees: current.oceanCurrentDirection
        )
    }
}

private enum OpenMeteoWeatherCodeConverter {
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

private struct OpenMeteoForecastResponse: Decodable {
    let timezone: String
    let current: OpenMeteoCurrentBlock
    let hourly: OpenMeteoHourlyBlock
    let daily: OpenMeteoDailyBlock
}

private struct OpenMeteoArchiveResponse: Decodable {
    let timezone: String
    let hourly: OpenMeteoHourlyBlock
    let daily: OpenMeteoDailyBlock
}

private struct OpenMeteoAirQualityResponse: Decodable {
    let current: OpenMeteoAirQualityCurrentBlock
}

private struct OpenMeteoAirQualityCurrentBlock: Decodable {
    let usAQI: Double?
    let pm10: Double?
    let pm25: Double?
    let carbonMonoxide: Double?
    let nitrogenDioxide: Double?
    let sulphurDioxide: Double?
    let ozone: Double?

    enum CodingKeys: String, CodingKey {
        case usAQI = "us_aqi"
        case pm10
        case pm25 = "pm2_5"
        case carbonMonoxide = "carbon_monoxide"
        case nitrogenDioxide = "nitrogen_dioxide"
        case sulphurDioxide = "sulphur_dioxide"
        case ozone
    }
}

private struct OpenMeteoMarineResponse: Decodable {
    let current: OpenMeteoMarineCurrentBlock?
}

private struct OpenMeteoMarineCurrentBlock: Decodable {
    let waveHeight: Double?
    let waveDirection: Double?
    let wavePeriod: Double?
    let windWaveHeight: Double?
    let swellWaveHeight: Double?
    let seaSurfaceTemperature: Double?
    let oceanCurrentVelocity: Double?
    let oceanCurrentDirection: Double?

    enum CodingKeys: String, CodingKey {
        case waveHeight = "wave_height"
        case waveDirection = "wave_direction"
        case wavePeriod = "wave_period"
        case windWaveHeight = "wind_wave_height"
        case swellWaveHeight = "swell_wave_height"
        case seaSurfaceTemperature = "sea_surface_temperature"
        case oceanCurrentVelocity = "ocean_current_velocity"
        case oceanCurrentDirection = "ocean_current_direction"
    }
}

private struct OpenMeteoCurrentBlock: Decodable {
    let time: String
    let temperature2M: Double
    let relativeHumidity2M: Double?
    let apparentTemperature: Double
    let isDay: Int
    let precipitation: Double?
    let weatherCode: Int
    let pressureMSL: Double?
    let cloudCover: Double?
    let windSpeed10M: Double
    let windDirection10M: Double?
    let windGusts10M: Double?
    let visibility: Double?

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2M = "temperature_2m"
        case relativeHumidity2M = "relative_humidity_2m"
        case apparentTemperature = "apparent_temperature"
        case isDay = "is_day"
        case precipitation
        case weatherCode = "weather_code"
        case pressureMSL = "pressure_msl"
        case cloudCover = "cloud_cover"
        case windSpeed10M = "wind_speed_10m"
        case windDirection10M = "wind_direction_10m"
        case windGusts10M = "wind_gusts_10m"
        case visibility
    }
}

private struct OpenMeteoHourlyBlock: Decodable {
    let time: [String]
    let temperature2M: [Double]?
    let relativeHumidity2M: [Double]?
    let apparentTemperature: [Double?]?
    let precipitationProbability: [Double?]?
    let precipitation: [Double?]?
    let weatherCode: [Int]?
    let pressureMSL: [Double?]?
    let cloudCover: [Double?]?
    let visibility: [Double?]?
    let windSpeed10M: [Double?]?
    let windDirection10M: [Double?]?
    let windGusts10M: [Double?]?
    let uvIndex: [Double?]?

    enum CodingKeys: String, CodingKey {
        case time
        case temperature2M = "temperature_2m"
        case relativeHumidity2M = "relative_humidity_2m"
        case apparentTemperature = "apparent_temperature"
        case precipitationProbability = "precipitation_probability"
        case precipitation
        case weatherCode = "weather_code"
        case pressureMSL = "pressure_msl"
        case cloudCover = "cloud_cover"
        case visibility
        case windSpeed10M = "wind_speed_10m"
        case windDirection10M = "wind_direction_10m"
        case windGusts10M = "wind_gusts_10m"
        case uvIndex = "uv_index"
    }
}

private struct OpenMeteoDailyBlock: Decodable {
    let time: [String]
    let weatherCode: [Int]?
    let temperature2MMax: [Double]?
    let temperature2MMin: [Double]?
    let sunrise: [String]?
    let sunset: [String]?
    let precipitationProbabilityMax: [Double?]?
    let precipitationSum: [Double?]?
    let windSpeed10MMax: [Double?]?
    let windDirection10MDominant: [Double?]?
    let uvIndexMax: [Double?]?

    enum CodingKeys: String, CodingKey {
        case time
        case weatherCode = "weather_code"
        case temperature2MMax = "temperature_2m_max"
        case temperature2MMin = "temperature_2m_min"
        case sunrise
        case sunset
        case precipitationProbabilityMax = "precipitation_probability_max"
        case precipitationSum = "precipitation_sum"
        case windSpeed10MMax = "wind_speed_10m_max"
        case windDirection10MDominant = "wind_direction_10m_dominant"
        case uvIndexMax = "uv_index_max"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

private func value(at index: Int, in values: [Double?]?) -> Double? {
    values?[safe: index] ?? nil
}
