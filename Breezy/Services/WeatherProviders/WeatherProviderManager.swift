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

    /// When both providers fail, skip the fallback attempt for a while so
    /// every refresh doesn't pay the latency of two doomed requests.
    private var lastBothProvidersFailedAt: Date?
    private let bothFailedCooldown: TimeInterval = 60

    func attribution() async -> AppWeatherAttribution? {
        await provider(for: selectedSource).attribution()
    }

    /// Fetches from the selected provider; on failure retries once with the
    /// alternate and marks the result. Cancellation is never retried.
    func fetchWeather(for location: LocationData, formatting: WeatherFormattingContext) async throws -> WeatherFetchResult {
        let primary = selectedSource
        do {
            return try await provider(for: primary).fetchWeather(for: location, formatting: formatting)
        } catch {
            let primaryError = error
            guard isRetryableProviderError(primaryError), shouldAttemptFallback() else { throw primaryError }

            let alternate: WeatherSource = primary == .weatherKit ? .openMeteo : .weatherKit
            do {
                var result = try await provider(for: alternate).fetchWeather(for: location, formatting: formatting)
                result.fallbackUsed = alternate
                return result
            } catch {
                lastBothProvidersFailedAt = Date()
                // Surface the primary's error — that's the provider the user picked.
                throw primaryError
            }
        }
    }

    func fetchHistoricalWeather(for location: LocationData, date: Date, formatting: WeatherFormattingContext) async throws -> WeatherInfo {
        try await provider(for: selectedSource).fetchHistoricalWeather(for: location, date: date, formatting: formatting)
    }

    func fetchHistoricalRange(for location: LocationData, startDate: Date, endDate: Date, formatting: WeatherFormattingContext) async throws -> [HistoricalDataPoint] {
        try await provider(for: selectedSource).fetchHistoricalRange(for: location, startDate: startDate, endDate: endDate, formatting: formatting)
    }

    private func shouldAttemptFallback() -> Bool {
        guard let last = lastBothProvidersFailedAt else { return true }
        return Date().timeIntervalSince(last) > bothFailedCooldown
    }

    private func isRetryableProviderError(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let urlError = error as? URLError, urlError.code == .cancelled { return false }
        return true
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
