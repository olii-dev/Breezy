//
//  AirQualityHelper.swift
//  Breezy
//
//  Air Quality Index utilities
//

import Foundation

struct AirQualityHelper {
    static func category(for aqi: Int) -> String {
        switch aqi {
        case 0...50:
            return "Good"
        case 51...100:
            return "Moderate"
        case 101...150:
            return "Unhealthy for Sensitive Groups"
        case 151...200:
            return "Unhealthy"
        case 201...300:
            return "Very Unhealthy"
        default:
            return "Hazardous"
        }
    }
    
    static func color(for aqi: Int) -> String {
        switch aqi {
        case 0...50:
            return "green"
        case 51...100:
            return "yellow"
        case 101...150:
            return "orange"
        case 151...200:
            return "red"
        case 201...300:
            return "purple"
        default:
            return "maroon"
        }
    }
    
    static func recommendation(for aqi: Int) -> String {
        switch aqi {
        case 0...50:
            return "Air quality is satisfactory. No health concerns."
        case 51...100:
            return "Acceptable for most. Sensitive groups may experience minor issues."
        case 101...150:
            return "Sensitive groups should reduce outdoor activity."
        case 151...200:
            return "Everyone may begin to experience health effects."
        case 201...300:
            return "Health alert: everyone may experience serious health effects."
        default:
            return "Health warning: avoid all outdoor activity."
        }
    }
}

