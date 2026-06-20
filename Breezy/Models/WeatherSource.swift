//
//  WeatherSource.swift
//  Breezy
//
//  Shared weather provider selection and capability metadata.
//

import Foundation

enum WeatherSource: String, CaseIterable, Identifiable, Codable {
    case weatherKit = "weatherkit"
    case openMeteo = "open-meteo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weatherKit:
            return "Apple Weather"
        case .openMeteo:
            return "Open-Meteo"
        }
    }

    var shortLabel: String {
        switch self {
        case .weatherKit:
            return "WeatherKit"
        case .openMeteo:
            return "Open-Meteo"
        }
    }

    var legalURL: URL? {
        switch self {
        case .weatherKit:
            return URL(string: "https://developer.apple.com/weatherkit/data-source-attribution/")
        case .openMeteo:
            return URL(string: "https://open-meteo.com/en/docs")
        }
    }

    var privacySummary: String {
        switch self {
        case .weatherKit:
            return "Weather forecasts are provided through Apple Weather and WeatherKit."
        case .openMeteo:
            return "Weather forecasts and historical weather are provided through Open-Meteo."
        }
    }
}

struct WeatherProviderCapabilities: Equatable {
    let source: WeatherSource
    let supportsMinuteForecast: Bool
    let supportsMoonData: Bool
    let historicalStartDate: Date?
    let supportedWidgets: Set<WidgetType>

    func supports(_ widgetType: WidgetType) -> Bool {
        supportedWidgets.contains(widgetType)
    }

    func unsupportedReason(for widgetType: WidgetType) -> String {
        switch widgetType {
        case .minutePrecipitation:
            return "\(source.displayName) does not provide Breezy's minute-by-minute precipitation feed."
        case .moonPhase:
            return "\(source.displayName) does not provide the moon phase data Breezy needs for this card."
        case .airQualityCard, .marineOutlook:
            return "\(source.displayName) does not provide this Open-Meteo-only widget."
        default:
            return "This widget is not available with \(source.displayName)."
        }
    }

    var historicalAvailabilityDescription: String {
        guard let historicalStartDate else {
            return "Historical weather is only available when your provider supports it."
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return "Historical weather is available from \(formatter.string(from: historicalStartDate)) onwards for most locations."
    }
}

extension WeatherSource {
    var capabilities: WeatherProviderCapabilities {
        switch self {
        case .weatherKit:
            return WeatherProviderCapabilities(
                source: self,
                supportsMinuteForecast: true,
                supportsMoonData: true,
                historicalStartDate: Calendar.current.date(from: DateComponents(year: 2021, month: 8, day: 1)),
                supportedWidgets: Set(WidgetType.allCases.filter { widget in
                    widget != .airQualityCard && widget != .marineOutlook
                })
            )
        case .openMeteo:
            return WeatherProviderCapabilities(
                source: self,
                supportsMinuteForecast: false,
                supportsMoonData: false,
                historicalStartDate: Calendar.current.date(from: DateComponents(year: 1940, month: 1, day: 1)),
                supportedWidgets: Set(WidgetType.allCases.filter { widget in
                    widget != .minutePrecipitation && widget != .moonPhase
                })
            )
        }
    }
}

extension WidgetType {
    func isSupported(by source: WeatherSource) -> Bool {
        source.capabilities.supports(self)
    }
}
