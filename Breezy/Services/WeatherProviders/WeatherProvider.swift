//
//  WeatherProvider.swift
//  Breezy
//
//  Shared provider abstractions and normalized weather payloads.
//

import Foundation

struct AppWeatherAttribution: Equatable {
    let providerName: String
    let legalPageURL: URL?
    let summary: String
}

struct WeatherFormattingContext {
    let temperatureUnit: TemperatureUnit
    let windSpeedUnit: WindSpeedUnit
    let pressureUnit: PressureUnit
    let visibilityUnit: VisibilityUnit
    let precipitationUnit: PrecipitationUnit

    var usesFahrenheit: Bool {
        temperatureUnit == .fahrenheit
    }

    func temperatureValue(fromCelsius celsius: Double) -> Double {
        usesFahrenheit ? ((celsius * 9.0 / 5.0) + 32.0) : celsius
    }

    func formattedTemperature(_ celsius: Double, includeUnit: Bool = true) -> String {
        let value = temperatureValue(fromCelsius: celsius)
        let suffix: String
        if includeUnit {
            suffix = usesFahrenheit ? "°F" : "°C"
        } else {
            suffix = "°"
        }
        return String(format: "%.0f%@", value, suffix)
    }

    func formattedWindSpeed(metersPerSecond: Double?) -> String? {
        guard let metersPerSecond else { return nil }
        let converted = windSpeedUnit.convert(metersPerSecond)
        return String(format: "%.0f %@", converted, windSpeedUnit.displayName)
    }

    func formattedWindGust(metersPerSecond: Double?) -> String? {
        guard let metersPerSecond else { return nil }
        let converted = windSpeedUnit.convert(metersPerSecond)
        return String(format: "%.0f %@", converted, windSpeedUnit.displayName)
    }

    func formattedPressure(hectopascals: Double?) -> String? {
        guard let hectopascals else { return nil }
        let converted = pressureUnit.convert(hectopascals)
        return String(format: "%.0f %@", converted, pressureUnit.displayName)
    }

    func formattedVisibility(meters: Double?) -> String? {
        guard let meters else { return nil }
        let converted = visibilityUnit.convert(meters)
        return String(format: "%.1f %@", converted, visibilityUnit.symbol)
    }

    func formattedPrecipitation(totalMillimeters: Double?) -> String? {
        guard let totalMillimeters else { return nil }
        let converted = precipitationUnit.convert(totalMillimeters)
        return String(format: "%.1f %@", converted, precipitationUnit.symbol)
    }

    func formattedPrecipitationRate(millimetersPerHour: Double?) -> String? {
        guard let millimetersPerHour else { return nil }
        let converted = precipitationUnit.convert(millimetersPerHour)
        return String(format: "%.1f %@/h", converted, precipitationUnit.symbol)
    }
}

struct ProviderCurrentWeather {
    let temperatureCelsius: Double
    let feelsLikeCelsius: Double
    let condition: String
    let conditionCode: String?
    let isDaylight: Bool
    let uvIndex: Int
    let pressureHectopascals: Double?
    let visibilityMeters: Double?
    let dewPointCelsius: Double?
    let humidityFraction: Double?
    let windDirectionDegrees: Double?
    let windSpeedMetersPerSecond: Double?
    let windGustMetersPerSecond: Double?
    let precipitationChance: Double?
    let precipitationIntensityMillimetersPerHour: Double?
    let cloudCoverFraction: Double?
    let airQuality: AirQuality?
    let marine: ProviderMarineConditions?
}

struct ProviderMarineConditions {
    let waveHeightMeters: Double?
    let waveDirectionDegrees: Double?
    let wavePeriodSeconds: Double?
    let swellHeightMeters: Double?
    let seaSurfaceTemperatureCelsius: Double?
    let currentSpeedMetersPerSecond: Double?
    let currentDirectionDegrees: Double?
}

struct ProviderHourlyWeather {
    let date: Date
    let temperatureCelsius: Double
    let condition: String
    let conditionCode: String?
    let precipitationChance: Double?
    let precipitationAmountMillimeters: Double?
    let windSpeedMetersPerSecond: Double?
    let windGustMetersPerSecond: Double?
    let windDirectionDegrees: Double?
    let uvIndex: Int?
    let humidityFraction: Double?
    let pressureHectopascals: Double?
    let visibilityMeters: Double?
    let cloudCoverFraction: Double?
}

struct ProviderDailyWeather {
    let date: Date
    let highTemperatureCelsius: Double
    let lowTemperatureCelsius: Double
    let condition: String
    let conditionCode: String?
    let precipitationChance: Double?
    let precipitationSumMillimeters: Double?
    let windSpeedMaxMetersPerSecond: Double?
    let windDirectionDegrees: Double?
    let uvIndexMax: Int?
    let sunrise: Date?
    let sunset: Date?
    let moonPhase: MoonPhase?
    let moonrise: Date?
    let moonset: Date?
}

struct ProviderWeatherPayload {
    let location: LocationData
    let timezone: TimeZone
    let current: ProviderCurrentWeather
    let hourly: [ProviderHourlyWeather]
    let daily: [ProviderDailyWeather]
    let minuteForecast: [MinuteForecast]
}

struct WeatherFetchResult {
    let weather: WeatherInfo
    let attribution: AppWeatherAttribution?
    let conditionCode: String?
    let isDaylight: Bool
}

protocol WeatherProviding {
    var source: WeatherSource { get }
    var capabilities: WeatherProviderCapabilities { get }

    func attribution() async -> AppWeatherAttribution?
    func fetchWeather(for location: LocationData, formatting: WeatherFormattingContext) async throws -> WeatherFetchResult
    func fetchHistoricalWeather(for location: LocationData, date: Date, formatting: WeatherFormattingContext) async throws -> WeatherInfo
    func fetchHistoricalRange(for location: LocationData, startDate: Date, endDate: Date, formatting: WeatherFormattingContext) async throws -> [HistoricalDataPoint]
}
