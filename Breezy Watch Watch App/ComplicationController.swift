//
//  ComplicationController.swift
//  Breezy Watch Watch App
//
//  Watch complications - circular only, simple and reliable
//

import ClockKit
import SwiftUI
import CoreLocation
import WeatherKit

// MARK: - Shared Data Model (from iOS app)

private struct SharedWeatherData: Codable {
    let city: String
    let temperature: String
    let condition: String
    let emoji: String
    let highTemp: String?
    let lowTemp: String?
    let hourlyForecast: [SharedHourlyForecast]
    let timestamp: Date
    let useMinimalistIcons: Bool?
    let uvIndex: Int?
    let pressure: String?
    let windSpeed: String?
    let rainChance: String?
    
    struct SharedHourlyForecast: Codable {
        let time: String
        let temperature: String
        let emoji: String
        let condition: String?
    }
}

class ComplicationController: NSObject, CLKComplicationDataSource {
    
    private let weatherService = WeatherService.shared
    
    // MARK: - Complication Configuration
    
    func getComplicationDescriptors(handler: @escaping ([CLKComplicationDescriptor]) -> Void) {
        let descriptor = CLKComplicationDescriptor(
            identifier: "BreezyWeather",
            displayName: "Breezy Weather",
            supportedFamilies: [
                .modularSmall,
                .modularLarge,
                .utilitarianSmall,
                .utilitarianSmallFlat,
                .utilitarianLarge,
                .circularSmall,
                .extraLarge,
                .graphicCorner,
                .graphicBezel,
                .graphicCircular,
                .graphicRectangular,
                .graphicExtraLarge
            ]
        )
        handler([descriptor])
    }
    
    // MARK: - Timeline Configuration
    
    func getTimelineStartDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        handler(Date())
    }
    
    func getTimelineEndDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        handler(Date().addingTimeInterval(24 * 60 * 60))
    }
    
    func getPrivacyBehavior(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void) {
        handler(.showOnLockScreen)
    }
    
    // MARK: - Timeline Population
    
    func getCurrentTimelineEntry(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void) {
        // Always try cached data first - this ensures we never show placeholders
        if let cachedData = loadCachedWeatherData() {
            let template = createTemplate(for: complication.family, weather: cachedData)
            let entry = CLKComplicationTimelineEntry(date: Date(), complicationTemplate: template)
            handler(entry)
            
            // Update cache in background and reload complications
            Task {
                if let _ = try? await fetchAndCacheWeather() {
                    // Reload complications with fresh data
                    await MainActor.run {
                        let server = CLKComplicationServer.sharedInstance()
                        if let activeComplications = server.activeComplications {
                            for comp in activeComplications {
                                server.reloadTimeline(for: comp)
                            }
                        }
                    }
                }
            }
            return
        }
        
        // No cache - return placeholder immediately, then fetch in background
        // This ensures the handler is called quickly (required by ClockKit)
        let placeholderWeather = WatchWeatherData(
            city: "Breezy",
            temperature: "--",
            feelsLike: nil,
            condition: "Loading",
            emoji: "🌡️",
            iconName: "thermometer",
            highTemp: nil,
            lowTemp: nil,
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
            sunset: nil
        )
        let placeholderTemplate = createTemplate(for: complication.family, weather: placeholderWeather)
        let placeholderEntry = CLKComplicationTimelineEntry(date: Date(), complicationTemplate: placeholderTemplate)
        handler(placeholderEntry)
        
        // Fetch fresh data in background and reload complications when done
        Task {
            if (try? await fetchAndCacheWeather()) != nil {
                // Reload complications with fresh data
                await MainActor.run {
                    let server = CLKComplicationServer.sharedInstance()
                    if let activeComplications = server.activeComplications {
                        for comp in activeComplications {
                            server.reloadTimeline(for: comp)
                        }
                    }
                }
            } else {
                // If fetch failed, try loading cache one more time (might have been updated)
                if loadCachedWeatherData() != nil {
                    await MainActor.run {
                        let server = CLKComplicationServer.sharedInstance()
                        if let activeComplications = server.activeComplications {
                            for comp in activeComplications {
                                server.reloadTimeline(for: comp)
                            }
                        }
                    }
                }
            }
        }
    }
    
    func getTimelineEntries(for complication: CLKComplication, after date: Date, limit: Int, withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void) {
        // Try to load cached data
        guard let weatherData = loadCachedWeatherData() else {
            // No cached data - return nil to let system handle it
            handler(nil)
            return
        }
        
        // Create future entries (though weather data will be the same)
        var entries: [CLKComplicationTimelineEntry] = []
        let calendar = Calendar.current
        
        // Create entries for next few hours (up to limit)
        // Create entries for next 6 hours
        for i in 1..<min(limit + 1, 6) {
            if let futureDate = calendar.date(byAdding: .hour, value: i, to: date) {
                // Find matching hourly forecast for this time
                let hourComponent = calendar.component(.hour, from: futureDate)
                let expectedTimeStr = WatchDateFormatterHelper.formatHour(hourComponent)
                
                var entryWeather = weatherData
                
                // If we have hourly data, use it to update the template
                if let hourly = weatherData.hourlyForecast.first(where: { $0.time == expectedTimeStr }) {
                    entryWeather = WatchWeatherData(
                        city: weatherData.city,
                        temperature: hourly.temperature,
                        feelsLike: nil,
                        condition: hourly.condition,
                        emoji: hourly.emoji,
                        iconName: hourly.iconName,
                        highTemp: weatherData.highTemp,
                        lowTemp: weatherData.lowTemp,
                        hourlyForecast: weatherData.hourlyForecast,
                        dailyForecast: weatherData.dailyForecast,
                        windSpeed: nil, windDirection: nil, windDirectionDegrees: nil, uvIndex: nil, rainChance: nil, humidity: nil,
                        pressure: nil, visibility: nil, dewPoint: nil, cloudCover: nil,
                        sunrise: nil, sunset: nil
                    )
                }
                
                let template = createTemplate(for: complication.family, weather: entryWeather)
                let entry = CLKComplicationTimelineEntry(date: futureDate, complicationTemplate: template)
                entries.append(entry)
            }
        }
        
        handler(entries.isEmpty ? nil : entries)
    }
    
    // MARK: - Sample Templates
    
    func getLocalizableSampleTemplate(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {
        // Create sample data for complication picker
        let sampleWeather = WatchWeatherData(
            city: "San Francisco",
            temperature: "72°F",
            feelsLike: nil,
            condition: "Sunny",
            emoji: "☀️",
            iconName: "sun.max.fill",
            highTemp: "75°F",
            lowTemp: "68°F",
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
            sunset: nil
        )
        
        let template = createTemplate(for: complication.family, weather: sampleWeather)
        handler(template)
    }
    
    // MARK: - Helper Methods
    
    private func loadCachedWeatherData() -> WatchWeatherData? {
        guard let defaults = UserDefaults(suiteName: "group.com.breezy.weather") else {
            return nil
        }
        
        // First, try to load from iOS app's shared data (most reliable)
        if let sharedData = defaults.data(forKey: "BreezyWidgetData"),
           let decoded = try? JSONDecoder().decode(SharedWeatherData.self, from: sharedData) {
            return WatchWeatherData(
                city: decoded.city,
                temperature: decoded.temperature,
                feelsLike: nil,
                condition: decoded.condition,
                emoji: decoded.emoji,
                iconName: "thermometer", // Fallback for shared data
                highTemp: decoded.highTemp,
                lowTemp: decoded.lowTemp,
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
                sunset: nil
            )
        }
        
        // Fallback to watch app's individual keys
        if let city = defaults.string(forKey: "WatchLastCity"),
           let temp = defaults.string(forKey: "WatchLastTemperature"),
           let condition = defaults.string(forKey: "WatchLastCondition"),
           let emoji = defaults.string(forKey: "WatchLastEmoji"),
           !city.isEmpty, !temp.isEmpty, !condition.isEmpty, !emoji.isEmpty {
            return WatchWeatherData(
                city: city,
                temperature: temp,
                feelsLike: nil,
                condition: condition,
                emoji: emoji,
                iconName: "thermometer", // Fallback for legacy cache
                highTemp: defaults.string(forKey: "WatchLastHighTemp"),
                lowTemp: defaults.string(forKey: "WatchLastLowTemp"),
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
                sunset: nil
            )
        }
        
        return nil
    }
    
    private func fetchAndCacheWeather() async throws -> WatchWeatherData {
        let defaults = UserDefaults(suiteName: "group.com.breezy.weather")
        
        // Get location - try multiple sources
        var location: CLLocation?
        
        // 1. Try watch app's cached location first
        if let defaults = defaults,
           defaults.object(forKey: "WatchLastLatitude") != nil,
           defaults.object(forKey: "WatchLastLongitude") != nil {
            let lat = defaults.double(forKey: "WatchLastLatitude")
            let lon = defaults.double(forKey: "WatchLastLongitude")
            if lat != 0 && lon != 0 {
                location = CLLocation(latitude: lat, longitude: lon)
            }
        }
        
        // 2. Try iOS app's shared data for location (if watch location not available)
        // Note: Shared data doesn't contain lat/lon, so we skip this step
        
        // 3. Try to get current location from watch
        if location == nil {
            let locationHelper = WatchLocationHelper()
            do {
                let locationData = try await locationHelper.requestLocationAndGetData(timeout: 8)
                location = CLLocation(latitude: locationData.latitude, longitude: locationData.longitude)
            } catch {
                // Location request failed - will try one more fallback below
            }
        }
        
        // 4. Last resort: try watch cached location one more time
        if location == nil, let defaults = defaults,
           defaults.object(forKey: "WatchLastLatitude") != nil,
           defaults.object(forKey: "WatchLastLongitude") != nil {
            let lat = defaults.double(forKey: "WatchLastLatitude")
            let lon = defaults.double(forKey: "WatchLastLongitude")
            if lat != 0 && lon != 0 {
                location = CLLocation(latitude: lat, longitude: lon)
            }
        }
        
        guard let clLocation = location else {
            throw NSError(domain: "Complication", code: 1, userInfo: [NSLocalizedDescriptionKey: "No location available"])
        }
        
        // Fetch weather
        let weather = try await weatherService.weather(for: clLocation)
        
        // Get temperature unit
        let temperatureUnit = WatchTemperatureUnit.fromUserDefaults()
        
        // Get current temperature
        let tempValue: Double
        if temperatureUnit == .fahrenheit {
            tempValue = weather.currentWeather.temperature.converted(to: .fahrenheit).value
        } else {
            tempValue = weather.currentWeather.temperature.converted(to: .celsius).value
        }
        let symbol = temperatureUnit.symbol
        let tempRaw = String(format: "%.0f°%@", tempValue, symbol)
        
        // Get condition
        let cond = WatchWeatherConditionConverter.description(from: weather.currentWeather.condition)
        let emoji = WatchWeatherIconHelper.emoji(for: cond)
        
        // Get today's high/low
        let (highTemp, lowTemp) = getTodayHighLow(from: weather.dailyForecast, unit: temperatureUnit)
        
        // Get city name
        let city = defaults?.string(forKey: "WatchLastCity") ?? "Current Location"
        
        // Cache everything
        if let defaults = defaults {
            defaults.set(clLocation.coordinate.latitude, forKey: "WatchLastLatitude")
            defaults.set(clLocation.coordinate.longitude, forKey: "WatchLastLongitude")
            defaults.set(city, forKey: "WatchLastCity")
            defaults.set(tempRaw, forKey: "WatchLastTemperature")
            defaults.set(cond, forKey: "WatchLastCondition")
            defaults.set(emoji, forKey: "WatchLastEmoji")
            defaults.set(highTemp, forKey: "WatchLastHighTemp")
            defaults.set(lowTemp, forKey: "WatchLastLowTemp")
            defaults.set(Date(), forKey: "WatchLastCacheTimestamp")
            defaults.synchronize()
        }
        
        // Parse hourly forecast (next 12h)
        let hourlyForecast = parseHourlyForecast(from: weather.hourlyForecast, unit: temperatureUnit)
        
        return WatchWeatherData(
            city: city,
            temperature: tempRaw,
            feelsLike: nil,
            condition: cond,
            emoji: emoji,
            iconName: WatchWeatherIconHelper.minimalistIcon(for: cond),
            highTemp: highTemp,
            lowTemp: lowTemp,
            hourlyForecast: hourlyForecast,
            dailyForecast: [],
            windSpeed: nil,
            windDirection: nil,
            windDirectionDegrees: weather.currentWeather.wind.direction.converted(to: .degrees).value,
            uvIndex: nil,
            rainChance: nil,
            humidity: nil,
            pressure: nil,
            visibility: nil,
            dewPoint: nil,
            cloudCover: nil,
            sunrise: nil,
            sunset: nil
        )
    }
    
    private func getTodayHighLow(from daily: Forecast<DayWeather>, unit: WatchTemperatureUnit) -> (high: String?, low: String?) {
        guard let today = daily.forecast.first else { return (nil, nil) }
        
        if unit == .fahrenheit {
            let maxF = today.highTemperature.converted(to: .fahrenheit).value
            let minF = today.lowTemperature.converted(to: .fahrenheit).value
            return (String(format: "%.0f°F", maxF), String(format: "%.0f°F", minF))
        } else {
            let maxC = today.highTemperature.converted(to: .celsius).value
            let minC = today.lowTemperature.converted(to: .celsius).value
            return (String(format: "%.0f°C", maxC), String(format: "%.0f°C", minC))
        }
    }
    
    // MARK: - Template Creation
    
    private func createTemplate(for family: CLKComplicationFamily, weather: WatchWeatherData) -> CLKComplicationTemplate {
        switch family {
        case .modularSmall:
            return CLKComplicationTemplateModularSmallSimpleText(
                textProvider: CLKSimpleTextProvider(text: weather.temperature)
            )
            
        case .modularLarge:
            return CLKComplicationTemplateModularLargeStandardBody(
                headerTextProvider: CLKSimpleTextProvider(text: weather.city),
                body1TextProvider: CLKSimpleTextProvider(text: weather.temperature),
                body2TextProvider: CLKSimpleTextProvider(text: weather.condition)
            )
            
        case .utilitarianSmall, .utilitarianSmallFlat:
            return CLKComplicationTemplateUtilitarianSmallFlat(
                textProvider: CLKSimpleTextProvider(text: "\(weather.emoji) \(weather.temperature)")
            )
            
        case .utilitarianLarge:
            return CLKComplicationTemplateUtilitarianLargeFlat(
                textProvider: CLKSimpleTextProvider(text: "\(weather.city) \(weather.temperature)")
            )
            
        case .circularSmall:
            return CLKComplicationTemplateCircularSmallStackText(
                line1TextProvider: CLKSimpleTextProvider(text: weather.emoji),
                line2TextProvider: CLKSimpleTextProvider(text: weather.temperature)
            )
            
        case .extraLarge:
            return CLKComplicationTemplateExtraLargeSimpleText(
                textProvider: CLKSimpleTextProvider(text: weather.temperature)
            )
            
        case .graphicCorner:
            return CLKComplicationTemplateGraphicCornerTextImage(
                textProvider: CLKSimpleTextProvider(text: weather.temperature),
                imageProvider: CLKFullColorImageProvider(fullColorImage: createWeatherImage(emoji: weather.emoji))
            )
            
        case .graphicBezel:
            return CLKComplicationTemplateGraphicBezelCircularText(
                circularTemplate: createGraphicCircularTemplate(weather: weather),
                textProvider: CLKSimpleTextProvider(text: weather.condition)
            )
            
        case .graphicCircular:
            return createGraphicCircularTemplate(weather: weather)
            
        case .graphicRectangular:
            return CLKComplicationTemplateGraphicRectangularStandardBody(
                headerTextProvider: CLKSimpleTextProvider(text: weather.city),
                body1TextProvider: CLKSimpleTextProvider(text: weather.temperature),
                body2TextProvider: CLKSimpleTextProvider(text: weather.condition)
            )
            
        case .graphicExtraLarge:
            return CLKComplicationTemplateGraphicExtraLargeCircularStackText(
                line1TextProvider: CLKSimpleTextProvider(text: weather.temperature),
                line2TextProvider: CLKSimpleTextProvider(text: weather.emoji)
            )
            
        @unknown default:
            // Fallback to circular small
            return CLKComplicationTemplateCircularSmallStackText(
                line1TextProvider: CLKSimpleTextProvider(text: weather.emoji),
                line2TextProvider: CLKSimpleTextProvider(text: weather.temperature)
            )
        }
    }
    
    private func createGraphicCircularTemplate(weather: WatchWeatherData) -> CLKComplicationTemplateGraphicCircular {
        return CLKComplicationTemplateGraphicCircularStackText(
            line1TextProvider: CLKSimpleTextProvider(text: weather.emoji),
            line2TextProvider: CLKSimpleTextProvider(text: weather.temperature)
        )
    }
    
    private func createWeatherImage(emoji: String) -> UIImage {
        // Create a simple image from emoji for graphic complications
        // Using watchOS-compatible graphics context API
        let size = CGSize(width: 40, height: 40)
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        
        let font = UIFont.systemFont(ofSize: 32)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let attributedString = NSAttributedString(string: emoji, attributes: attributes)
        let textSize = attributedString.size()
        let textRect = CGRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        attributedString.draw(in: textRect)
        
        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }

    
    private func parseHourlyForecast(from hourlyForecast: Forecast<HourWeather>, unit: WatchTemperatureUnit) -> [WatchHourlyForecast] {
        var forecasts: [WatchHourlyForecast] = []
        let calendar = Calendar.current
        let now = Date()
        let endTime = calendar.date(byAdding: .hour, value: 12, to: now)!
        
        // Filter to next 12 hours
        let relevantHours = hourlyForecast.forecast.filter { hour in
            hour.date >= now && hour.date < endTime
        }
        
        // Sort by date
        let sortedHours = relevantHours.sorted { $0.date < $1.date }
        
        for hour in sortedHours {
            let hourInt = calendar.component(.hour, from: hour.date)
            
            // Only show every 3 hours (0, 3, 6, 9, 12, 15, 18, 21) if needed, 
            // but for complications we might want every hour if we are updating frequently.
            // Let's keep every hour for better resolution in timeline.
            
            let tempRaw: Double
            if unit == .fahrenheit {
                tempRaw = hour.temperature.converted(to: .fahrenheit).value
            } else {
                tempRaw = hour.temperature.converted(to: .celsius).value
            }
            
            let weatherDesc = WatchWeatherConditionConverter.description(from: hour.condition)
            let timeDisplay = WatchDateFormatterHelper.formatHour(hourInt)
            let emoji = WatchWeatherIconHelper.emoji(for: weatherDesc)
            let iconName = WatchWeatherIconHelper.minimalistIcon(for: weatherDesc)
            
            forecasts.append(WatchHourlyForecast(
                date: hour.date,
                time: timeDisplay,
                temperature: String(format: "%.0f°%@", tempRaw, unit.symbol),
                emoji: emoji,
                iconName: iconName,
                condition: weatherDesc
            ))
        }
        
        return forecasts
    }
}

