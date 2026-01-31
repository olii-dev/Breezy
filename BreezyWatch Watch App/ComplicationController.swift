//
//  ComplicationController.swift
//  BreezyWatch Watch App
//
//  Watch complications
//

import ClockKit
import SwiftUI

// MARK: - Shared Widget Data Model

struct WidgetWeatherData: Codable {
    let city: String
    let temperature: String
    let condition: String
    let emoji: String
    let highTemp: String?
    let lowTemp: String?
    let hourlyForecast: [WidgetHourlyForecast]
    let timestamp: Date
    let useMinimalistIcons: Bool?
    let uvIndex: Int?
    let pressure: String?
    let windSpeed: String?
    let rainChance: String?
    
    struct WidgetHourlyForecast: Codable {
        let time: String
        let temperature: String
        let emoji: String
        let condition: String?
    }
}

class ComplicationController: NSObject, CLKComplicationDataSource {
    
    // MARK: - Complication Configuration
    
    func getComplicationDescriptors(handler: @escaping ([CLKComplicationDescriptor]) -> Void) {
        let descriptors = [
            CLKComplicationDescriptor(
                identifier: "complication",
                displayName: "Breezy Weather",
                supportedFamilies: CLKComplicationFamily.allCases
            )
        ]
        handler(descriptors)
    }
    
    // MARK: - Timeline Configuration
    
    func getTimelineStartDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        handler(Date())
    }
    
    func getTimelineEndDate(for complication: CLKComplication, withHandler handler: @escaping (Date?) -> Void) {
        handler(Date().addingTimeInterval(24 * 60 * 60)) // 24 hours
    }
    
    func getPrivacyBehavior(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void) {
        handler(.showOnLockScreen)
    }
    
    // MARK: - Timeline Population
    
    func getCurrentTimelineEntry(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void) {
        // Load weather data from shared App Group
        guard let defaults = UserDefaults(suiteName: "group.com.breezy.weather"),
              let data = defaults.data(forKey: "BreezyWidgetData"),
              let widgetData = try? JSONDecoder().decode(WidgetWeatherData.self, from: data) else {
            handler(nil)
            return
        }
        
        let template = createTemplate(for: complication.family, weather: widgetData)
        let entry = CLKComplicationTimelineEntry(date: Date(), complicationTemplate: template)
        handler(entry)
    }
    
    func getTimelineEntries(for complication: CLKComplication, after date: Date, limit: Int, withHandler handler: @escaping ([CLKComplicationTimelineEntry]?) -> Void) {
        handler(nil)
    }
    
    // MARK: - Sample Templates
    
    func getLocalizableSampleTemplate(for complication: CLKComplication, withHandler handler: @escaping (CLKComplicationTemplate?) -> Void) {
        // Create sample data
        let sampleData = WidgetWeatherData(
            city: "San Francisco",
            temperature: "72°F",
            condition: "Sunny",
            emoji: "☀️",
            highTemp: "75°F",
            lowTemp: "68°F",
            hourlyForecast: [],
            timestamp: Date(),
            useMinimalistIcons: nil,
            uvIndex: nil,
            pressure: nil,
            windSpeed: nil,
            rainChance: nil
        )
        
        let template = createTemplate(for: complication.family, weather: sampleData)
        handler(template)
    }
    
    // MARK: - Template Creation
    
    private func createTemplate(for family: CLKComplicationFamily, weather: WidgetWeatherData) -> CLKComplicationTemplate {
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
            
        case .utilitarianSmall:
            return CLKComplicationTemplateUtilitarianSmallFlat(
                textProvider: CLKSimpleTextProvider(text: "\(weather.emoji) \(weather.temperature)")
            )
            
        case .utilitarianSmallFlat:
            return CLKComplicationTemplateUtilitarianSmallFlat(
                textProvider: CLKSimpleTextProvider(text: "\(weather.emoji) \(weather.temperature)")
            )
            
        case .utilitarianLarge:
            return CLKComplicationTemplateUtilitarianLargeFlat(
                textProvider: CLKSimpleTextProvider(text: "\(weather.city) \(weather.temperature)")
            )
            
        case .circularSmall:
            return CLKComplicationTemplateCircularSmallSimpleText(
                textProvider: CLKSimpleTextProvider(text: weather.temperature)
            )
            
        case .extraLarge:
            return CLKComplicationTemplateExtraLargeSimpleText(
                textProvider: CLKSimpleTextProvider(text: weather.temperature)
            )
            
        case .graphicCorner:
            return CLKComplicationTemplateGraphicCornerTextImage(
                textProvider: CLKSimpleTextProvider(text: weather.temperature),
                imageProvider: CLKFullColorImageProvider(fullColorImage: UIImage(systemName: "cloud.sun.fill") ?? UIImage())
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
            return CLKComplicationTemplateModularSmallSimpleText(
                textProvider: CLKSimpleTextProvider(text: weather.temperature)
            )
        }
    }
    
    private func createGraphicCircularTemplate(weather: WidgetWeatherData) -> CLKComplicationTemplateGraphicCircular {
        return CLKComplicationTemplateGraphicCircularStackText(
            line1TextProvider: CLKSimpleTextProvider(text: weather.temperature),
            line2TextProvider: CLKSimpleTextProvider(text: weather.emoji)
        )
    }
}

