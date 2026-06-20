//
//  WeatherKitProvider.swift
//  Breezy
//
//  Apple Weather implementation of Breezy's provider protocol.
//

import CoreLocation
import Foundation
import WeatherKit

final class WeatherKitProvider: WeatherProviding {
    static let shared = WeatherKitProvider()

    let source: WeatherSource = .weatherKit
    let capabilities: WeatherProviderCapabilities = WeatherSource.weatherKit.capabilities

    private let weatherService = WeatherService.shared

    private init() {}

    func attribution() async -> AppWeatherAttribution? {
        do {
            let attribution = try await weatherService.attribution
            return AppWeatherAttribution(
                providerName: source.displayName,
                legalPageURL: attribution.legalPageURL,
                summary: source.privacySummary
            )
        } catch {
            return AppWeatherAttribution(
                providerName: source.displayName,
                legalPageURL: source.legalURL,
                summary: source.privacySummary
            )
        }
    }

    func fetchWeather(for location: LocationData, formatting: WeatherFormattingContext) async throws -> WeatherFetchResult {
        let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let weather = try await weatherService.weather(for: clLocation)
        let timezone = await resolveTimeZone(for: clLocation)
        let payload = makePayload(location: location, weather: weather, timezone: timezone)
        let info = ProviderWeatherMapper.makeWeatherInfo(from: payload, formatting: formatting)

        return WeatherFetchResult(
            weather: info,
            attribution: await attribution(),
            conditionCode: weather.currentWeather.condition.description,
            isDaylight: weather.currentWeather.isDaylight
        )
    }

    func fetchHistoricalWeather(for location: LocationData, date: Date, formatting: WeatherFormattingContext) async throws -> WeatherInfo {
        let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let timezone = await resolveTimeZone(for: clLocation)
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay.addingTimeInterval(86_400)

        let dailyCollection = try await weatherService.weather(for: clLocation, including: .daily(startDate: startOfDay, endDate: endOfDay))
        let hourlyCollection = try await weatherService.weather(for: clLocation, including: .hourly(startDate: startOfDay, endDate: endOfDay))

        guard let day = dailyCollection.first else {
            throw NSError(domain: "Breezy.WeatherKit", code: 404, userInfo: [NSLocalizedDescriptionKey: "No historical data found"])
        }

        let hourly = hourlyCollection.map { mapHourly($0) }
        let representative = formatting.usesFahrenheit
            ? day.highTemperature.converted(to: .fahrenheit).value
            : day.highTemperature.converted(to: .celsius).value
        let representativeCelsius = formatting.usesFahrenheit ? ((representative - 32.0) * 5.0 / 9.0) : representative

        return ProviderWeatherMapper.makeHistoricalWeatherInfo(
            location: location,
            timezone: timezone,
            condition: WeatherConditionConverter.description(from: day.condition),
            representativeTemperatureCelsius: representativeCelsius,
            highTemperatureCelsius: day.highTemperature.converted(to: .celsius).value,
            lowTemperatureCelsius: day.lowTemperature.converted(to: .celsius).value,
            hourly: hourly,
            formatting: formatting,
            rainChance: day.precipitationChance,
            rainfallTotalMillimeters: day.precipitationAmount.value,
            sunrise: day.sun.sunrise,
            sunset: day.sun.sunset,
            uvIndex: Int(day.uvIndex.value),
            windSpeedMetersPerSecond: day.wind.speed.converted(to: .metersPerSecond).value,
            windGustMetersPerSecond: hourly.compactMap(\.windGustMetersPerSecond).max(),
            windDirectionDegrees: day.wind.direction.value,
            feelsLikeCelsius: nil,
            humidityFraction: hourly.compactMap(\.humidityFraction).first,
            pressureHectopascals: hourly.compactMap(\.pressureHectopascals).first,
            visibilityMeters: hourly.compactMap(\.visibilityMeters).first,
            cloudCoverFraction: hourly.compactMap(\.cloudCoverFraction).first
        )
    }

    func fetchHistoricalRange(for location: LocationData, startDate: Date, endDate: Date, formatting: WeatherFormattingContext) async throws -> [HistoricalDataPoint] {
        let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let dailyCollection = try await weatherService.weather(for: clLocation, including: .daily(startDate: startDate, endDate: endDate))

        let mapped = dailyCollection.map { day in
            ProviderDailyWeather(
                date: day.date,
                highTemperatureCelsius: day.highTemperature.converted(to: .celsius).value,
                lowTemperatureCelsius: day.lowTemperature.converted(to: .celsius).value,
                condition: WeatherConditionConverter.description(from: day.condition),
                conditionCode: day.condition.description,
                precipitationChance: day.precipitationChance,
                precipitationSumMillimeters: day.precipitationAmount.value,
                windSpeedMaxMetersPerSecond: day.wind.speed.converted(to: .metersPerSecond).value,
                windDirectionDegrees: day.wind.direction.value,
                uvIndexMax: Int(day.uvIndex.value),
                sunrise: day.sun.sunrise,
                sunset: day.sun.sunset,
                moonPhase: extractMoonPhase(from: day),
                moonrise: day.moon.moonrise,
                moonset: day.moon.moonset
            )
        }

        return ProviderWeatherMapper.makeHistoricalRange(from: mapped)
    }

    private func makePayload(location: LocationData, weather: Weather, timezone: TimeZone) -> ProviderWeatherPayload {
        let current = ProviderCurrentWeather(
            temperatureCelsius: weather.currentWeather.temperature.converted(to: .celsius).value,
            feelsLikeCelsius: weather.currentWeather.apparentTemperature.converted(to: .celsius).value,
            condition: WeatherConditionConverter.description(from: weather.currentWeather.condition),
            conditionCode: weather.currentWeather.condition.description,
            isDaylight: weather.currentWeather.isDaylight,
            uvIndex: Int(weather.currentWeather.uvIndex.value),
            pressureHectopascals: weather.currentWeather.pressure.converted(to: .hectopascals).value,
            visibilityMeters: weather.currentWeather.visibility.converted(to: .meters).value,
            dewPointCelsius: weather.currentWeather.dewPoint.converted(to: .celsius).value,
            humidityFraction: weather.currentWeather.humidity,
            windDirectionDegrees: weather.currentWeather.wind.direction.converted(to: .degrees).value,
            windSpeedMetersPerSecond: weather.currentWeather.wind.speed.converted(to: .metersPerSecond).value,
            windGustMetersPerSecond: weather.hourlyForecast.first?.wind.gust?.converted(to: .metersPerSecond).value,
            precipitationChance: weather.dailyForecast.first?.precipitationChance,
            precipitationIntensityMillimetersPerHour: weather.minuteForecast?.forecast.first?.precipitationIntensity.value,
            cloudCoverFraction: weather.currentWeather.cloudCover,
            airQuality: nil,
            marine: nil
        )

        let hourly = weather.hourlyForecast.map(mapHourly)
        let daily = weather.dailyForecast.map { day in
            ProviderDailyWeather(
                date: day.date,
                highTemperatureCelsius: day.highTemperature.converted(to: .celsius).value,
                lowTemperatureCelsius: day.lowTemperature.converted(to: .celsius).value,
                condition: WeatherConditionConverter.description(from: day.condition),
                conditionCode: day.condition.description,
                precipitationChance: day.precipitationChance,
                precipitationSumMillimeters: day.precipitationAmount.value,
                windSpeedMaxMetersPerSecond: day.wind.speed.converted(to: .metersPerSecond).value,
                windDirectionDegrees: day.wind.direction.value,
                uvIndexMax: Int(day.uvIndex.value),
                sunrise: day.sun.sunrise,
                sunset: day.sun.sunset,
                moonPhase: extractMoonPhase(from: day),
                moonrise: day.moon.moonrise,
                moonset: day.moon.moonset
            )
        }

        let minuteForecast = weather.minuteForecast?.forecast.map { minute in
            MinuteForecast(
                time: minute.date,
                precipitationChance: minute.precipitationChance,
                precipitationIntensity: minute.precipitationIntensity.value,
                isPrecipitating: minute.precipitationChance > 0
            )
        } ?? []

        return ProviderWeatherPayload(
            location: location,
            timezone: timezone,
            current: current,
            hourly: hourly,
            daily: daily,
            minuteForecast: minuteForecast
        )
    }

    private func mapHourly(_ hour: HourWeather) -> ProviderHourlyWeather {
        ProviderHourlyWeather(
            date: hour.date,
            temperatureCelsius: hour.temperature.converted(to: .celsius).value,
            condition: WeatherConditionConverter.description(from: hour.condition),
            conditionCode: hour.condition.description,
            precipitationChance: hour.precipitationChance,
            precipitationAmountMillimeters: hour.precipitationAmount.value,
            windSpeedMetersPerSecond: hour.wind.speed.converted(to: .metersPerSecond).value,
            windGustMetersPerSecond: hour.wind.gust?.converted(to: .metersPerSecond).value,
            windDirectionDegrees: hour.wind.direction.value,
            uvIndex: Int(hour.uvIndex.value),
            humidityFraction: hour.humidity,
            pressureHectopascals: hour.pressure.converted(to: .hectopascals).value,
            visibilityMeters: hour.visibility.converted(to: .meters).value,
            cloudCoverFraction: hour.cloudCover
        )
    }

    private func extractMoonPhase(from day: DayWeather) -> MoonPhase? {
        let calendar = Calendar.current
        let daysSinceReference = calendar.dateComponents([.day], from: calendar.startOfDay(for: day.date), to: Date()).day ?? 0
        let illumination = abs(sin(Double(daysSinceReference % 29) / 29.0 * 2.0 * .pi))
        let phaseName = MoonPhaseHelper.phaseName(from: illumination)
        let icon = MoonPhaseHelper.icon(for: phaseName)
        return MoonPhase(phase: phaseName, illumination: illumination, icon: icon)
    }

    private func resolveTimeZone(for location: CLLocation) async -> TimeZone {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        return placemarks?.first?.timeZone ?? .current
    }
}
