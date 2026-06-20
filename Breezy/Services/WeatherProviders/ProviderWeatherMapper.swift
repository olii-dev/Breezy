//
//  ProviderWeatherMapper.swift
//  Breezy
//
//  Maps normalized provider payloads into Breezy's app models.
//

import Foundation

enum ProviderWeatherMapper {
    static func makeWeatherInfo(from payload: ProviderWeatherPayload, formatting: WeatherFormattingContext) -> WeatherInfo {
        let timezone = payload.timezone
        let hourlyDisplay = makeTodayHourlyForecast(from: payload.hourly, formatting: formatting, timezone: timezone)
        let allHourly = makeAllHourlyForecast(from: payload.hourly, formatting: formatting, timezone: timezone)
        let dailyDisplay = makeDailyForecast(from: payload.daily, hourly: payload.hourly, formatting: formatting, timezone: timezone)
        let metrics = makeMetrics(from: payload, formatting: formatting, timezone: timezone)

        return WeatherInfo(
            location: locationWithTimezone(payload.location, timezone: timezone),
            temperature: formatting.formattedTemperature(payload.current.temperatureCelsius),
            feelsLike: formatting.formattedTemperature(payload.current.feelsLikeCelsius),
            highTemp: payload.daily.first.map { formatting.formattedTemperature($0.highTemperatureCelsius) },
            lowTemp: payload.daily.first.map { formatting.formattedTemperature($0.lowTemperatureCelsius) },
            condition: payload.current.condition,
            emoji: WeatherIconHelper.emoji(for: payload.current.condition),
            hourlyForecast: hourlyDisplay,
            allHourlyData: allHourly,
            dailyForecast: dailyDisplay,
            metrics: metrics,
            timezone: timezone.identifier
        )
    }

    static func makeHistoricalWeatherInfo(
        location: LocationData,
        timezone: TimeZone,
        condition: String,
        representativeTemperatureCelsius: Double,
        highTemperatureCelsius: Double,
        lowTemperatureCelsius: Double,
        hourly: [ProviderHourlyWeather],
        formatting: WeatherFormattingContext,
        rainChance: Double?,
        rainfallTotalMillimeters: Double?,
        sunrise: Date?,
        sunset: Date?,
        uvIndex: Int?,
        windSpeedMetersPerSecond: Double?,
        windGustMetersPerSecond: Double?,
        windDirectionDegrees: Double?,
        feelsLikeCelsius: Double?,
        humidityFraction: Double?,
        pressureHectopascals: Double?,
        visibilityMeters: Double?,
        cloudCoverFraction: Double?
    ) -> WeatherInfo {
        let detailedHourly = makeAllHourlyForecast(from: hourly, formatting: formatting, timezone: timezone)
        let summaryHourly = makeThreeHourForecast(from: hourly, formatting: formatting, timezone: timezone)

        let metrics = WeatherMetrics(
            uvIndex: uvIndex,
            uvIndexCategory: uvIndex.map { UVIndexHelper.category(for: $0) },
            airQuality: nil,
            marine: nil,
            pressure: formatting.formattedPressure(hectopascals: pressureHectopascals),
            visibility: formatting.formattedVisibility(meters: visibilityMeters),
            dewPoint: nil,
            humidity: humidityFraction.map { Int(round($0 * 100)) },
            windDirection: windDirectionDegrees,
            windDirectionCardinal: windDirectionDegrees.map { WindDirectionHelper.cardinalDirection(from: $0) },
            windSpeed: formatting.formattedWindSpeed(metersPerSecond: windSpeedMetersPerSecond),
            windGust: formatting.formattedWindGust(metersPerSecond: windGustMetersPerSecond),
            rainChance: rainChance.map { String(format: "%.0f%%", $0 * 100) },
            todayRainfall: formatting.formattedPrecipitation(totalMillimeters: rainfallTotalMillimeters),
            todayMaxRainIntensity: nil,
            cloudCover: cloudCoverFraction.map { String(format: "%.0f%%", $0 * 100) },
            sunrise: sunrise.map { DateFormatterHelper.formatTime($0, timeZone: timezone) },
            sunset: sunset.map { DateFormatterHelper.formatTime($0, timeZone: timezone) },
            minuteForecast: nil
        )

        return WeatherInfo(
            location: locationWithTimezone(location, timezone: timezone),
            temperature: formatting.formattedTemperature(representativeTemperatureCelsius),
            feelsLike: feelsLikeCelsius.map { formatting.formattedTemperature($0) },
            highTemp: formatting.formattedTemperature(highTemperatureCelsius, includeUnit: false),
            lowTemp: formatting.formattedTemperature(lowTemperatureCelsius, includeUnit: false),
            condition: condition,
            emoji: WeatherIconHelper.emoji(for: condition),
            hourlyForecast: summaryHourly,
            allHourlyData: detailedHourly,
            dailyForecast: [],
            metrics: metrics,
            timezone: timezone.identifier
        )
    }

    static func makeHistoricalRange(from daily: [ProviderDailyWeather]) -> [HistoricalDataPoint] {
        daily.map { day in
            HistoricalDataPoint(
                date: day.date,
                temperature: (day.highTemperatureCelsius + day.lowTemperatureCelsius) / 2.0,
                high: day.highTemperatureCelsius,
                low: day.lowTemperatureCelsius,
                condition: day.condition
            )
        }
    }

    private static func makeTodayHourlyForecast(
        from hourly: [ProviderHourlyWeather],
        formatting: WeatherFormattingContext,
        timezone: TimeZone
    ) -> [HourlyForecast] {
        var calendar = Calendar.current
        calendar.timeZone = timezone
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday.addingTimeInterval(86_400)

        let todayHours = hourly
            .filter { $0.date >= startOfToday && $0.date < startOfTomorrow }
            .sorted { $0.date < $1.date }

        return todayHours.compactMap { hour in
            let hourValue = calendar.component(.hour, from: hour.date)
            guard hourValue % 3 == 0 else { return nil }
            return makeHourlyForecast(from: hour, formatting: formatting, timezone: timezone)
        }
    }

    private static func makeAllHourlyForecast(
        from hourly: [ProviderHourlyWeather],
        formatting: WeatherFormattingContext,
        timezone: TimeZone
    ) -> [HourlyForecast] {
        hourly
            .sorted { $0.date < $1.date }
            .map { makeHourlyForecast(from: $0, formatting: formatting, timezone: timezone) }
    }

    private static func makeThreeHourForecast(
        from hourly: [ProviderHourlyWeather],
        formatting: WeatherFormattingContext,
        timezone: TimeZone
    ) -> [HourlyForecast] {
        var calendar = Calendar.current
        calendar.timeZone = timezone

        return hourly
            .sorted { $0.date < $1.date }
            .compactMap { hour in
                let hourValue = calendar.component(.hour, from: hour.date)
                guard hourValue % 3 == 0 else { return nil }
                return makeHourlyForecast(from: hour, formatting: formatting, timezone: timezone)
            }
    }

    private static func makeDailyForecast(
        from daily: [ProviderDailyWeather],
        hourly: [ProviderHourlyWeather],
        formatting: WeatherFormattingContext,
        timezone: TimeZone
    ) -> [DailyForecast] {
        var calendar = Calendar.current
        calendar.timeZone = timezone

        return daily.prefix(10).enumerated().map { index, day in
            let dayStart = calendar.startOfDay(for: day.date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)

            let dayHourly = hourly
                .filter { $0.date >= dayStart && $0.date < dayEnd }
                .sorted { $0.date < $1.date }

            let summaryHourly = dayHourly.compactMap { hour -> HourlyForecast? in
                let hourValue = calendar.component(.hour, from: hour.date)
                guard hourValue % 3 == 0 else { return nil }
                return makeHourlyForecast(from: hour, formatting: formatting, timezone: timezone)
            }

            let detailedHourly = dayHourly.map { makeHourlyForecast(from: $0, formatting: formatting, timezone: timezone) }
            let humidityValues = detailedHourly.compactMap(\.humidity)
            let averageHumidity = humidityValues.isEmpty ? nil : Int(round(Double(humidityValues.reduce(0, +)) / Double(humidityValues.count)))

            return DailyForecast(
                date: DateFormatterHelper.dateFormatter.string(from: day.date),
                dayName: index == 0 ? "Today" : DateFormatterHelper.formatDayName(day.date, timeZone: timezone),
                highTemp: formatting.formattedTemperature(day.highTemperatureCelsius, includeUnit: false),
                lowTemp: formatting.formattedTemperature(day.lowTemperatureCelsius, includeUnit: false),
                condition: day.condition,
                emoji: WeatherIconHelper.emoji(for: day.condition),
                chanceOfRain: day.precipitationChance.map { String(format: "%.0f%%", $0 * 100) },
                windSpeed: formatting.formattedWindSpeed(metersPerSecond: day.windSpeedMaxMetersPerSecond),
                windDirection: day.windDirectionDegrees,
                windDirectionCardinal: day.windDirectionDegrees.map { WindDirectionHelper.cardinalDirection(from: $0) },
                humidity: averageHumidity.map { "\($0)%" },
                sunrise: day.sunrise.map { DateFormatterHelper.formatTime($0, timeZone: timezone) },
                sunset: day.sunset.map { DateFormatterHelper.formatTime($0, timeZone: timezone) },
                sunriseDate: day.sunrise,
                sunsetDate: day.sunset,
                moonPhase: day.moonPhase,
                moonrise: day.moonrise.map { DateFormatterHelper.formatTime($0, timeZone: timezone) },
                moonset: day.moonset.map { DateFormatterHelper.formatTime($0, timeZone: timezone) },
                hourlyData: summaryHourly.isEmpty ? detailedHourly : summaryHourly,
                allHourlyData: detailedHourly.isEmpty ? nil : detailedHourly
            )
        }
    }

    private static func makeMetrics(
        from payload: ProviderWeatherPayload,
        formatting: WeatherFormattingContext,
        timezone: TimeZone
    ) -> WeatherMetrics {
        let current = payload.current
        let today = payload.daily.first

        let todayHours = hoursForToday(payload.hourly, timezone: timezone)
        let todayRainfall = todayHours.reduce(0.0) { $0 + ($1.precipitationAmountMillimeters ?? 0) }
        let todayMaxIntensity = todayHours.compactMap(\.precipitationAmountMillimeters).max()

        return WeatherMetrics(
            uvIndex: current.uvIndex,
            uvIndexCategory: UVIndexHelper.category(for: current.uvIndex),
            airQuality: current.airQuality,
            marine: current.marine.map { marine in
                MarineConditions(
                    waveHeight: marine.waveHeightMeters.map { String(format: "%.1f m", $0) },
                    waveDirection: marine.waveDirectionDegrees.map { WindDirectionHelper.cardinalDirection(from: $0) },
                    wavePeriod: marine.wavePeriodSeconds.map { String(format: "%.0f s", $0) },
                    swellHeight: marine.swellHeightMeters.map { String(format: "%.1f m", $0) },
                    seaSurfaceTemperature: marine.seaSurfaceTemperatureCelsius.map { formatting.formattedTemperature($0) },
                    currentSpeed: formatting.formattedWindSpeed(metersPerSecond: marine.currentSpeedMetersPerSecond),
                    currentDirection: marine.currentDirectionDegrees.map { WindDirectionHelper.cardinalDirection(from: $0) }
                )
            },
            pressure: formatting.formattedPressure(hectopascals: current.pressureHectopascals),
            visibility: formatting.formattedVisibility(meters: current.visibilityMeters),
            dewPoint: current.dewPointCelsius.map { formatting.formattedTemperature($0, includeUnit: false) },
            humidity: current.humidityFraction.map { Int(round($0 * 100)) },
            windDirection: current.windDirectionDegrees,
            windDirectionCardinal: current.windDirectionDegrees.map { WindDirectionHelper.cardinalDirection(from: $0) },
            windSpeed: formatting.formattedWindSpeed(metersPerSecond: current.windSpeedMetersPerSecond),
            windGust: formatting.formattedWindGust(metersPerSecond: current.windGustMetersPerSecond),
            rainChance: today?.precipitationChance.map { String(format: "%.0f%%", $0 * 100) },
            todayRainfall: todayHours.isEmpty ? nil : formatting.formattedPrecipitation(totalMillimeters: todayRainfall),
            todayMaxRainIntensity: formatting.formattedPrecipitationRate(millimetersPerHour: todayMaxIntensity),
            cloudCover: current.cloudCoverFraction.map { String(format: "%.0f%%", $0 * 100) },
            sunrise: today?.sunrise.map { DateFormatterHelper.formatTime($0, timeZone: timezone) },
            sunset: today?.sunset.map { DateFormatterHelper.formatTime($0, timeZone: timezone) },
            minuteForecast: payload.minuteForecast.isEmpty ? nil : payload.minuteForecast
        )
    }

    private static func hoursForToday(_ hourly: [ProviderHourlyWeather], timezone: TimeZone) -> [ProviderHourlyWeather] {
        var calendar = Calendar.current
        calendar.timeZone = timezone
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday.addingTimeInterval(86_400)
        return hourly.filter { $0.date >= startOfToday && $0.date < startOfTomorrow }
    }

    private static func makeHourlyForecast(
        from hour: ProviderHourlyWeather,
        formatting: WeatherFormattingContext,
        timezone: TimeZone
    ) -> HourlyForecast {
        var calendar = Calendar.current
        calendar.timeZone = timezone
        let hourValue = calendar.component(.hour, from: hour.date)

        return HourlyForecast(
            sourceDate: hour.date,
            time: DateFormatterHelper.formatHour(hourValue),
            temperatureRaw: formatting.temperatureValue(fromCelsius: hour.temperatureCelsius),
            condition: hour.condition,
            emoji: WeatherIconHelper.emoji(for: hour.condition),
            hourValue: hourValue,
            precipitationChance: hour.precipitationChance,
            precipitationAmount: hour.precipitationAmountMillimeters,
            windSpeed: formatting.formattedWindSpeed(metersPerSecond: hour.windSpeedMetersPerSecond),
            windGust: hour.windGustMetersPerSecond.map { formatting.windSpeedUnit.convert($0) },
            windDirection: hour.windDirectionDegrees.map { WindDirectionHelper.cardinalDirection(from: $0) },
            uvIndex: hour.uvIndex,
            humidity: hour.humidityFraction.map { Int(round($0 * 100)) }
        )
    }

    private static func locationWithTimezone(_ location: LocationData, timezone: TimeZone) -> LocationData {
        var updatedLocation = location
        updatedLocation.timezoneIdentifier = timezone.identifier
        return updatedLocation
    }
}
