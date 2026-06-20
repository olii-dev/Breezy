//
//  WeatherProviderManager.swift
//  Breezy
//
//  Routes Breezy weather requests to the selected provider.
//

import Foundation

final class WeatherProviderManager {
    static let shared = WeatherProviderManager()

    private init() {}

    var selectedSource: WeatherSource {
        WeatherSourceStore.selectedSource
    }

    var capabilities: WeatherProviderCapabilities {
        provider(for: selectedSource).capabilities
    }

    func attribution() async -> AppWeatherAttribution? {
        await provider(for: selectedSource).attribution()
    }

    func fetchWeather(for location: LocationData, formatting: WeatherFormattingContext) async throws -> WeatherFetchResult {
        try await provider(for: selectedSource).fetchWeather(for: location, formatting: formatting)
    }

    func fetchHistoricalWeather(for location: LocationData, date: Date, formatting: WeatherFormattingContext) async throws -> WeatherInfo {
        try await provider(for: selectedSource).fetchHistoricalWeather(for: location, date: date, formatting: formatting)
    }

    func fetchHistoricalRange(for location: LocationData, startDate: Date, endDate: Date, formatting: WeatherFormattingContext) async throws -> [HistoricalDataPoint] {
        try await provider(for: selectedSource).fetchHistoricalRange(for: location, startDate: startDate, endDate: endDate, formatting: formatting)
    }

    private func provider(for source: WeatherSource) -> WeatherProviding {
        switch source {
        case .weatherKit:
            return WeatherKitProvider.shared
        case .openMeteo:
            return OpenMeteoProvider.shared
        }
    }
}
