//
//  WatchWeatherDataService.swift
//  Breezy Watch Watch App
//
//  Shared fetch, parse, and cache pipeline for watch weather data.
//

import CoreLocation
import Foundation
import WeatherKit

final class WatchWeatherDataService {
    static let shared = WatchWeatherDataService()

    private let weatherService = WeatherService.shared
    private let locationHelper = WatchLocationHelper()

    private init() {}

    func fetchWeather(selectedLocation: WatchSavedLocation?) async throws -> WatchWeatherData {
        let source = selectedWeatherSource()

        do {
            if let selectedLocation {
                if let phoneReply = try? await WatchSessionManager.shared.requestWeatherData(
                    for: CLLocationCoordinate2D(latitude: selectedLocation.latitude, longitude: selectedLocation.longitude)
                ) {
                    let parsed = parsePhoneData(
                        phoneReply,
                        city: selectedLocation.name,
                        latitude: selectedLocation.latitude,
                        longitude: selectedLocation.longitude,
                        isStale: false
                    )
                    cache(parsed)
                    return parsed
                }

                let weather = try await fetchFromSelectedSource(
                    source: source,
                    latitude: selectedLocation.latitude,
                    longitude: selectedLocation.longitude,
                    city: selectedLocation.name
                )
                cache(weather)
                return weather
            }

            if let phoneReply = try? await WatchSessionManager.shared.requestWeatherData(for: nil) {
                let city = phoneReply["city"] as? String ?? "Current Location"
                let latitude = phoneReply["latitude"] as? Double ?? phoneReply["lat"] as? Double
                let longitude = phoneReply["longitude"] as? Double ?? phoneReply["lon"] as? Double
                let parsed = parsePhoneData(
                    phoneReply,
                    city: city,
                    latitude: latitude,
                    longitude: longitude,
                    isStale: false
                )
                cache(parsed)
                return parsed
            }

            let gpsData = try await locationHelper.requestLocationAndGetData()
            let weather = try await fetchFromSelectedSource(
                source: source,
                latitude: gpsData.latitude,
                longitude: gpsData.longitude,
                city: gpsData.city
            )
            cache(weather)
            return weather
        } catch {
            if let cached = loadCachedWeather(markStale: true) {
                return cached
            }
            throw error
        }
    }

    func refreshStoredSelectionWeather() async throws -> WatchWeatherData {
        try await fetchWeather(selectedLocation: loadStoredSelection())
    }

    func loadCachedWeather(markStale: Bool = true) -> WatchWeatherData? {
        guard let defaults = UserDefaults(suiteName: WatchAppStorageKey.appGroup) else {
            return nil
        }

        let selectedSource = selectedWeatherSource()
        if let cachedSourceRaw = defaults.string(forKey: WatchAppStorageKey.lastWeatherSource),
           let cachedSource = WatchWeatherDataSource(rawValue: cachedSourceRaw) {
            let matchesSelection = (selectedSource == .weatherKit && cachedSource == .weatherKit)
                || (selectedSource == .openMeteo && cachedSource == .openMeteo)
                || cachedSource == .phone
                || cachedSource == .cache
            guard matchesSelection else { return nil }
        }

        guard let city = defaults.string(forKey: WatchAppStorageKey.lastCity),
              let temperature = defaults.string(forKey: WatchAppStorageKey.lastTemperature),
              let condition = defaults.string(forKey: WatchAppStorageKey.lastCondition),
              let emoji = defaults.string(forKey: WatchAppStorageKey.lastEmoji),
              !city.isEmpty,
              !temperature.isEmpty,
              !condition.isEmpty,
              !emoji.isEmpty else {
            return nil
        }

        let timestamp = defaults.object(forKey: WatchAppStorageKey.lastCacheTimestamp) as? Date ?? .distantPast
        let latitude = defaults.object(forKey: WatchAppStorageKey.lastLatitude) as? Double
        let longitude = defaults.object(forKey: WatchAppStorageKey.lastLongitude) as? Double
        let source = defaults.string(forKey: WatchAppStorageKey.lastWeatherSource)
            .flatMap(WatchWeatherDataSource.init(rawValue:))
            ?? .cache

        return WatchWeatherData(
            city: city,
            temperature: temperature,
            feelsLike: nil,
            condition: condition,
            emoji: emoji,
            iconName: WatchWeatherIconHelper.minimalistIcon(for: condition),
            highTemp: defaults.string(forKey: WatchAppStorageKey.lastHighTemp),
            lowTemp: defaults.string(forKey: WatchAppStorageKey.lastLowTemp),
            hourlyForecast: [],
            dailyForecast: [],
            windSpeed: nil,
            windDirection: nil,
            windDirectionDegrees: nil,
            uvIndex: nil,
            rainChance: nil,
            humidity: nil,
            pressure: nil,
            visibility: nil,
            dewPoint: nil,
            cloudCover: nil,
            sunrise: nil,
            sunset: nil,
            metadata: WatchWeatherMetadata(
                source: source == .cache ? .cache : source,
                fetchedAt: timestamp,
                isStale: markStale,
                latitude: latitude,
                longitude: longitude
            )
        )
    }

    private func loadStoredSelection() -> WatchSavedLocation? {
        guard let defaults = UserDefaults(suiteName: WatchAppStorageKey.appGroup),
              let selectedIDString = defaults.string(forKey: WatchAppStorageKey.selectedLocationID),
              let selectedID = UUID(uuidString: selectedIDString),
              let data = defaults.data(forKey: WatchAppStorageKey.savedLocations),
              let savedLocations = try? JSONDecoder().decode([WatchSavedLocation].self, from: data) else {
            return nil
        }

        return savedLocations.first(where: { $0.id == selectedID })
    }

    private func cache(_ weather: WatchWeatherData) {
        guard let defaults = UserDefaults(suiteName: WatchAppStorageKey.appGroup) else {
            return
        }

        defaults.set(weather.metadata.latitude, forKey: WatchAppStorageKey.lastLatitude)
        defaults.set(weather.metadata.longitude, forKey: WatchAppStorageKey.lastLongitude)
        defaults.set(weather.city, forKey: WatchAppStorageKey.lastCity)
        defaults.set(weather.temperature, forKey: WatchAppStorageKey.lastTemperature)
        defaults.set(weather.condition, forKey: WatchAppStorageKey.lastCondition)
        defaults.set(weather.emoji, forKey: WatchAppStorageKey.lastEmoji)
        defaults.set(weather.highTemp, forKey: WatchAppStorageKey.lastHighTemp)
        defaults.set(weather.lowTemp, forKey: WatchAppStorageKey.lastLowTemp)
        defaults.set(weather.metadata.fetchedAt, forKey: WatchAppStorageKey.lastCacheTimestamp)
        defaults.set(weather.metadata.source.rawValue, forKey: WatchAppStorageKey.lastWeatherSource)
        defaults.synchronize()
    }

    private func selectedWeatherSource() -> WatchSelectedWeatherSource {
        let defaults = UserDefaults(suiteName: WatchAppStorageKey.appGroup) ?? .standard
        return defaults.string(forKey: WatchAppStorageKey.weatherSource)
            .flatMap(WatchSelectedWeatherSource.init(rawValue:))
            ?? defaults.string(forKey: WatchAppStorageKey.phoneWeatherSource)
                .flatMap(WatchSelectedWeatherSource.init(rawValue:))
            ?? .weatherKit
    }

    private func fetchFromSelectedSource(
        source: WatchSelectedWeatherSource,
        latitude: Double,
        longitude: Double,
        city: String
    ) async throws -> WatchWeatherData {
        switch source {
        case .weatherKit:
            return try await fetchFromWeatherKit(latitude: latitude, longitude: longitude, city: city)
        case .openMeteo:
            return try await WatchOpenMeteoClient.shared.fetchWeather(
                latitude: latitude,
                longitude: longitude,
                city: city,
                units: currentUnits()
            )
        }
    }

    private func fetchFromWeatherKit(latitude: Double, longitude: Double, city: String) async throws -> WatchWeatherData {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let weather = try await weatherService.weather(for: location)
        let units = currentUnits()
        let hourly = parseHourlyForecast(from: weather.hourlyForecast, temperatureUnit: units.temperature)
        let daily = parseDailyForecast(from: weather.dailyForecast, hourlyForecast: hourly, temperatureUnit: units.temperature, windUnit: units.wind)
        let metrics = extractMetrics(
            from: weather.currentWeather,
            daily: weather.dailyForecast,
            temperatureUnit: units.temperature,
            windUnit: units.wind,
            pressureUnit: units.pressure,
            visibilityUnit: units.visibility
        )
        let temperatures = currentTemperatures(from: weather.currentWeather, temperatureUnit: units.temperature)
        let condition = WatchWeatherConditionConverter.description(from: weather.currentWeather.condition)

        return WatchWeatherData(
            city: city,
            temperature: formattedTemperature(temperatures.temp, unit: units.temperature),
            feelsLike: formattedTemperature(temperatures.feels, unit: units.temperature),
            condition: condition,
            emoji: WatchWeatherIconHelper.emoji(for: condition),
            iconName: WatchWeatherIconHelper.minimalistIcon(for: condition),
            highTemp: todayHighLow(from: weather.dailyForecast, temperatureUnit: units.temperature).high,
            lowTemp: todayHighLow(from: weather.dailyForecast, temperatureUnit: units.temperature).low,
            hourlyForecast: Array(hourly.prefix(24)),
            dailyForecast: daily,
            windSpeed: metrics.windSpeed,
            windDirection: metrics.windDirection,
            windDirectionDegrees: metrics.windDirectionDegrees,
            uvIndex: metrics.uvIndex,
            rainChance: metrics.rainChance,
            humidity: metrics.humidity,
            pressure: metrics.pressure,
            visibility: metrics.visibility,
            dewPoint: metrics.dewPoint,
            cloudCover: metrics.cloudCover,
            sunrise: metrics.sunrise,
            sunset: metrics.sunset,
            metadata: WatchWeatherMetadata(
                source: .weatherKit,
                fetchedAt: Date(),
                isStale: false,
                latitude: latitude,
                longitude: longitude
            )
        )
    }

    private func parsePhoneData(
        _ data: [String: Any],
        city: String,
        latitude: Double?,
        longitude: Double?,
        isStale: Bool
    ) -> WatchWeatherData {
        let units = currentUnits()

        func formatPhoneTemperature(_ celsius: Double?) -> String {
            guard let celsius else { return "--" }
            if units.temperature == .fahrenheit {
                return String(format: "%.0f°F", (celsius * 9 / 5) + 32)
            }
            return String(format: "%.0f°C", celsius)
        }

        let condition = data["condition"] as? String ?? "Unknown"
        let windMps = data["wind_mps"] as? Double ?? 0
        let pressureHpa = data["pressure_hpa"] as? Double
        let visibilityKm = data["visibility_km"] as? Double
        let dewPointC = data["dew_c"] as? Double
        let humidityValue = Int(((data["humidity"] as? Double) ?? 0) * 100)
        let rainChance = String(format: "%.0f%%", ((data["rainChance"] as? Double) ?? 0) * 100)
        let sunriseTime = (data["sunrise"] as? TimeInterval).map { WatchDateFormatterHelper.formatTime(Date(timeIntervalSince1970: $0)) }
        let sunsetTime = (data["sunset"] as? TimeInterval).map { WatchDateFormatterHelper.formatTime(Date(timeIntervalSince1970: $0)) }

        let hourlyForecast: [WatchHourlyForecast] = (data["hourly"] as? [[String: Any]] ?? []).compactMap { hour in
            guard let timestamp = hour["time"] as? TimeInterval,
                  let tempC = hour["temp_c"] as? Double,
                  let hourCondition = hour["condition"] as? String else {
                return nil
            }

            let date = Date(timeIntervalSince1970: timestamp)
            return WatchHourlyForecast(
                date: date,
                time: WatchDateFormatterHelper.formatHour(Calendar.current.component(.hour, from: date)),
                temperature: formatPhoneTemperature(tempC),
                emoji: WatchWeatherIconHelper.emoji(for: hourCondition),
                iconName: WatchWeatherIconHelper.minimalistIcon(for: hourCondition),
                condition: hourCondition
            )
        }

        let dailyForecast: [WatchDailyForecast] = (data["daily"] as? [[String: Any]] ?? []).compactMap { day in
            guard let timestamp = day["time"] as? TimeInterval,
                  let lowC = day["low_c"] as? Double,
                  let highC = day["high_c"] as? Double,
                  let dayCondition = day["condition"] as? String else {
                return nil
            }

            let date = Date(timeIntervalSince1970: timestamp)
            let lowValue = units.temperature == .fahrenheit ? (lowC * 9 / 5) + 32 : lowC
            let highValue = units.temperature == .fahrenheit ? (highC * 9 / 5) + 32 : highC
            return WatchDailyForecast(
                dayName: Calendar.current.isDateInToday(date) ? "Today" : shortWeekday(for: date),
                iconName: WatchWeatherIconHelper.minimalistIcon(for: dayCondition),
                emoji: WatchWeatherIconHelper.emoji(for: dayCondition),
                lowTemp: String(format: "%.0f°", lowValue),
                highTemp: String(format: "%.0f°", highValue),
                lowValue: lowValue,
                highValue: highValue,
                condition: dayCondition,
                precipitationChance: String(format: "%.0f%%", ((day["rainChance"] as? Double) ?? 0) * 100),
                maxWindSpeed: formatWindSpeed(windMps, unit: units.wind),
                uvIndex: String(format: "%d", Int((day["uv"] as? Double) ?? 0)),
                sunrise: (day["sunrise"] as? TimeInterval).map { WatchDateFormatterHelper.formatTime(Date(timeIntervalSince1970: $0)) },
                sunset: (day["sunset"] as? TimeInterval).map { WatchDateFormatterHelper.formatTime(Date(timeIntervalSince1970: $0)) },
                hourlyForecast: []
            )
        }

        return WatchWeatherData(
            city: city,
            temperature: formatPhoneTemperature(data["temp_c"] as? Double),
            feelsLike: formatPhoneTemperature(data["feels_c"] as? Double),
            condition: condition,
            emoji: WatchWeatherIconHelper.emoji(for: condition),
            iconName: WatchWeatherIconHelper.minimalistIcon(for: condition),
            highTemp: formatPhoneTemperature(data["high_c"] as? Double),
            lowTemp: formatPhoneTemperature(data["low_c"] as? Double),
            hourlyForecast: hourlyForecast,
            dailyForecast: dailyForecast.isEmpty ? [
                WatchDailyForecast(
                    dayName: "Today",
                    iconName: WatchWeatherIconHelper.minimalistIcon(for: condition),
                    emoji: WatchWeatherIconHelper.emoji(for: condition),
                    lowTemp: formatPhoneTemperature(data["low_c"] as? Double),
                    highTemp: formatPhoneTemperature(data["high_c"] as? Double),
                    lowValue: data["low_c"] as? Double ?? 0,
                    highValue: data["high_c"] as? Double ?? 0,
                    condition: condition,
                    precipitationChance: rainChance,
                    maxWindSpeed: formatWindSpeed(windMps, unit: units.wind),
                    uvIndex: String(format: "%d", Int((data["uv"] as? Double) ?? 0)),
                    sunrise: sunriseTime,
                    sunset: sunsetTime,
                    hourlyForecast: hourlyForecast
                )
            ] : dailyForecast,
            windSpeed: formatWindSpeed(windMps, unit: units.wind),
            windDirection: nil,
            windDirectionDegrees: nil,
            uvIndex: Int((data["uv"] as? Double) ?? 0),
            rainChance: rainChance,
            humidity: humidityValue,
            pressure: formatPressure(pressureHpa, unit: units.pressure),
            visibility: formatVisibility(visibilityKm, unit: units.visibility),
            dewPoint: formatPhoneTemperature(dewPointC),
            cloudCover: String(format: "%.0f%%", ((data["cloud"] as? Double) ?? 0) * 100),
            sunrise: sunriseTime,
            sunset: sunsetTime,
            metadata: WatchWeatherMetadata(
                source: .phone,
                fetchedAt: Date(),
                isStale: isStale,
                latitude: latitude,
                longitude: longitude
            )
        )
    }

    private func currentUnits() -> (temperature: WatchTemperatureUnit, wind: WindSpeedUnit, pressure: PressureUnit, visibility: VisibilityUnit) {
        let defaults = UserDefaults(suiteName: WatchAppStorageKey.appGroup) ?? .standard
        let wind = defaults.string(forKey: WatchAppStorageKey.windSpeedUnit).flatMap(WindSpeedUnit.init(rawValue:)) ?? .metersPerSecond
        let pressure = defaults.string(forKey: WatchAppStorageKey.pressureUnit).flatMap(PressureUnit.init(rawValue:)) ?? .hectopascals
        let visibility = defaults.string(forKey: WatchAppStorageKey.visibilityUnit).flatMap(VisibilityUnit.init(rawValue:)) ?? .kilometers
        return (WatchTemperatureUnit.fromUserDefaults(), wind, pressure, visibility)
    }

    private func currentTemperatures(from currentWeather: CurrentWeather, temperatureUnit: WatchTemperatureUnit) -> (temp: Double, feels: Double) {
        if temperatureUnit == .fahrenheit {
            return (
                currentWeather.temperature.converted(to: .fahrenheit).value,
                currentWeather.apparentTemperature.converted(to: .fahrenheit).value
            )
        }

        return (
            currentWeather.temperature.converted(to: .celsius).value,
            currentWeather.apparentTemperature.converted(to: .celsius).value
        )
    }

    private func todayHighLow(from daily: Forecast<DayWeather>, temperatureUnit: WatchTemperatureUnit) -> (high: String?, low: String?) {
        guard let today = daily.forecast.first else {
            return (nil, nil)
        }

        if temperatureUnit == .fahrenheit {
            return (
                String(format: "%.0f°F", today.highTemperature.converted(to: .fahrenheit).value),
                String(format: "%.0f°F", today.lowTemperature.converted(to: .fahrenheit).value)
            )
        }

        return (
            String(format: "%.0f°C", today.highTemperature.converted(to: .celsius).value),
            String(format: "%.0f°C", today.lowTemperature.converted(to: .celsius).value)
        )
    }

    private func parseHourlyForecast(from hourlyForecast: Forecast<HourWeather>, temperatureUnit: WatchTemperatureUnit) -> [WatchHourlyForecast] {
        hourlyForecast.forecast.map { hour in
            let temperature = temperatureUnit == .fahrenheit
                ? hour.temperature.converted(to: .fahrenheit).value
                : hour.temperature.converted(to: .celsius).value
            let condition = WatchWeatherConditionConverter.description(from: hour.condition)

            return WatchHourlyForecast(
                date: hour.date,
                time: WatchDateFormatterHelper.formatHour(Calendar.current.component(.hour, from: hour.date)),
                temperature: formattedTemperature(temperature, unit: temperatureUnit),
                emoji: WatchWeatherIconHelper.emoji(for: condition),
                iconName: WatchWeatherIconHelper.minimalistIcon(for: condition),
                condition: condition
            )
        }
    }

    private func parseDailyForecast(
        from dailyForecast: Forecast<DayWeather>,
        hourlyForecast: [WatchHourlyForecast],
        temperatureUnit: WatchTemperatureUnit,
        windUnit: WindSpeedUnit
    ) -> [WatchDailyForecast] {
        let calendar = Calendar.current

        return dailyForecast.forecast.prefix(7).map { day in
            let lowValue = temperatureUnit == .fahrenheit
                ? day.lowTemperature.converted(to: .fahrenheit).value
                : day.lowTemperature.converted(to: .celsius).value
            let highValue = temperatureUnit == .fahrenheit
                ? day.highTemperature.converted(to: .fahrenheit).value
                : day.highTemperature.converted(to: .celsius).value
            let condition = WatchWeatherConditionConverter.description(from: day.condition)

            return WatchDailyForecast(
                dayName: calendar.isDateInToday(day.date) ? "Today" : shortWeekday(for: day.date),
                iconName: WatchWeatherIconHelper.minimalistIcon(for: condition),
                emoji: WatchWeatherIconHelper.emoji(for: condition),
                lowTemp: String(format: "%.0f°", lowValue),
                highTemp: String(format: "%.0f°", highValue),
                lowValue: lowValue,
                highValue: highValue,
                condition: condition,
                precipitationChance: String(format: "%.0f%%", day.precipitationChance * 100),
                maxWindSpeed: formatWindSpeed(day.wind.speed.converted(to: .metersPerSecond).value, unit: windUnit),
                uvIndex: String(Int(day.uvIndex.value)),
                sunrise: day.sun.sunrise.map(WatchDateFormatterHelper.formatTime),
                sunset: day.sun.sunset.map(WatchDateFormatterHelper.formatTime),
                hourlyForecast: hourlyForecast.filter { calendar.isDate($0.date, inSameDayAs: day.date) }
            )
        }
    }

    private func extractMetrics(
        from currentWeather: CurrentWeather,
        daily: Forecast<DayWeather>,
        temperatureUnit: WatchTemperatureUnit,
        windUnit: WindSpeedUnit,
        pressureUnit: PressureUnit,
        visibilityUnit: VisibilityUnit
    ) -> WatchWeatherMetrics {
        WatchWeatherMetrics(
            windSpeed: formatWindSpeed(currentWeather.wind.speed.converted(to: .metersPerSecond).value, unit: windUnit),
            windDirection: WatchWindDirectionHelper.cardinalDirection(from: currentWeather.wind.direction.converted(to: .degrees).value),
            windDirectionDegrees: currentWeather.wind.direction.converted(to: .degrees).value,
            uvIndex: Int(currentWeather.uvIndex.value),
            rainChance: daily.forecast.first.map { String(format: "%.0f%%", $0.precipitationChance * 100) },
            humidity: Int(currentWeather.humidity * 100),
            pressure: formatPressure(currentWeather.pressure.converted(to: .hectopascals).value, unit: pressureUnit),
            visibility: formatVisibility(currentWeather.visibility.converted(to: .kilometers).value, unit: visibilityUnit),
            dewPoint: formattedTemperature(
                temperatureUnit == .fahrenheit
                    ? currentWeather.dewPoint.converted(to: .fahrenheit).value
                    : currentWeather.dewPoint.converted(to: .celsius).value,
                unit: temperatureUnit
            ),
            cloudCover: String(format: "%.0f%%", currentWeather.cloudCover * 100),
            sunrise: daily.forecast.first?.sun.sunrise.map(WatchDateFormatterHelper.formatTime),
            sunset: daily.forecast.first?.sun.sunset.map(WatchDateFormatterHelper.formatTime)
        )
    }

    private func formattedTemperature(_ value: Double, unit: WatchTemperatureUnit) -> String {
        String(format: "%.0f°%@", value, unit.symbol)
    }

    private func formatWindSpeed(_ metersPerSecond: Double, unit: WindSpeedUnit) -> String {
        String(format: "%.0f %@", unit.convert(metersPerSecond), unit.displayName)
    }

    private func formatPressure(_ hectopascals: Double?, unit: PressureUnit) -> String? {
        guard let hectopascals else { return nil }
        let converted = unit.convert(hectopascals)
        switch unit {
        case .inchesOfMercury:
            return String(format: "%.2f inHg", converted)
        case .millimetersOfMercury:
            return String(format: "%.0f mmHg", converted)
        case .millibars:
            return String(format: "%.0f mbar", converted)
        case .hectopascals:
            return String(format: "%.0f hPa", converted)
        }
    }

    private func formatVisibility(_ kilometers: Double?, unit: VisibilityUnit) -> String? {
        guard let kilometers else { return nil }
        return String(format: "%.1f %@", unit.convert(kilometers * 1000), unit.symbol)
    }

    private func shortWeekday(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}
