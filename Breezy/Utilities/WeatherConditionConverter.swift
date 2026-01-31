//
//  WeatherConditionConverter.swift
//  Breezy
//
//  Converts WeatherKit condition enum to string
//

import Foundation
import Combine
import WeatherKit

class WeatherConditionConverter {
    static func description(from condition: WeatherCondition) -> String {
        switch condition {
        case .clear:
            return "Clear"
        case .cloudy:
            return "Cloudy"
        case .foggy:
            return "Foggy"
        case .haze:
            return "Haze"
        case .mostlyClear:
            return "Mostly Clear"
        case .mostlyCloudy:
            return "Mostly Cloudy"
        case .partlyCloudy:
            return "Partly Cloudy"
        case .smoky:
            return "Smoky"
        case .breezy:
            return "Breezy"
        case .windy:
            return "Windy"
        case .drizzle:
            return "Drizzle"
        case .heavyRain:
            return "Heavy Rain"
        case .rain:
            return "Rain"
        case .sunShowers:
            return "Sun Showers"
        case .blowingDust:
            return "Blowing Dust"
        case .freezingDrizzle:
            return "Freezing Drizzle"
        case .freezingRain:
            return "Freezing Rain"
        case .sleet:
            return "Sleet"
        case .snow:
            return "Snow"
        case .heavySnow:
            return "Heavy Snow"
        case .sunFlurries:
            return "Sun Flurries"
        case .flurries:
            return "Flurries"
        case .blowingSnow:
            return "Blowing Snow"
        case .blizzard:
            return "Blizzard"
        case .frigid:
            return "Frigid"
        case .hot:
            return "Hot"
        case .hail:
            return "Hail"
        case .scatteredThunderstorms:
            return "Scattered Thunderstorms"
        case .strongStorms:
            return "Strong Storms"
        case .thunderstorms:
            return "Thunderstorms"
        case .isolatedThunderstorms:
            return "Isolated Thunderstorms"
        case .tropicalStorm:
            return "Tropical Storm"
        case .hurricane:
            return "Hurricane"
        @unknown default:
            return "Unknown"
        }
    }
}

