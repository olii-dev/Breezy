//
//  WatchSessionManagerStub.swift
//  BreezyMac
//
//  macOS stand-in for the iOS WatchSessionManager (WatchConnectivity does not
//  exist on macOS). Matches the surface the shared code touches so the
//  ViewModel and app lifecycle compile unchanged.
//

import Foundation
import Combine

final class WatchSessionManager {
    static let shared = WatchSessionManager()

    /// Mirrors the iOS manager's activation hook so observers compile.
    var onSessionActivation: (() -> Void)?

    private init() {}

    func startSession() {
        // Nothing to sync without a watch companion on macOS.
    }

    func updateContext(
        weatherSource: WeatherSource,
        useMinimalistIcons: Bool,
        typography: WeatherFont,
        visibleMetrics: Set<WeatherMetric>,
        temperatureUnit: TemperatureUnit,
        windSpeedUnit: WindSpeedUnit,
        pressureUnit: PressureUnit,
        visibilityUnit: VisibilityUnit,
        precipitationUnit: PrecipitationUnit,
        themeMode: WeatherViewModel.ThemeMode,
        presetTheme: String,
        currentTheme: WeatherTheme,
        customTheme: WeatherTheme,
        mapStyle: WeatherViewModel.RadarMapStyle,
        radarPrecipitationSource: RadarPrecipitationSource
    ) {
        // No-op on macOS.
    }
}
