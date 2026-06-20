//
//  WatchSessionManager.swift
//  Breezy
//
//  Manages Watch Connectivity session on iOS
//

import Foundation
import WatchConnectivity
import Combine
import CoreLocation

class WatchSessionManager: NSObject, WCSessionDelegate, ObservableObject {
    static let shared = WatchSessionManager()
    
    private let locationHelper = LocationHelper()
    
    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    
    // Callback to trigger sync when session is ready
    var onSessionActivation: (() -> Void)? {
        didSet {
            // If already active when handler is set, trigger immediately
            if session?.activationState == .activated {
                DispatchQueue.main.async {
                    self.onSessionActivation?()
                }
            }
        }
    }
    
    private override init() {
        super.init()
        session?.delegate = self
        session?.activate()
    }
    
    func startSession() {
        // Just ensures init is called
        if session?.activationState != .activated {
            session?.activate()
        }
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
        guard let session = session, session.activationState == .activated else { return }
        
        var context: [String: Any] = [
            "useMinimalistIcons": useMinimalistIcons,
            "typography": typography.rawValue,
            WeatherSourceStore.storageKey: weatherSource.rawValue,
            "Breezy.temperatureUnit": temperatureUnit.rawValue,
            "Breezy.windSpeedUnit": windSpeedUnit.rawValue,
            "Breezy.pressureUnit": pressureUnit.displayName, // ID is rawValue
            "Breezy.visibilityUnit": visibilityUnit.rawValue,
            "Breezy.precipitationUnit": precipitationUnit.rawValue,
            "Breezy.themeMode": themeMode.rawValue,
            "Breezy.presetTheme": presetTheme,
            "Breezy.mapStyle": mapStyle.rawValue,
            RadarPrecipitationSource.storageKey: radarPrecipitationSource.rawValue
        ]
        
        // Direct Color Sync (Bypassing Watch logic)
        let topHex = currentTheme.topColor.toHex()
        let bottomHex = currentTheme.bottomColor.toHex()
        let textHex = currentTheme.textColor.toHex()
        
        print("🎨 PHONE: Syncing Theme. Hex Values -> Top: \(topHex ?? "NIL"), Bottom: \(bottomHex ?? "NIL"), Text: \(textHex ?? "NIL")")
            
        if let top = topHex, let bottom = bottomHex, let text = textHex {
            context["theme.top"] = top
            context["theme.bottom"] = bottom
            context["theme.text"] = text
        } else {
            print("⚠️ PHONE: Failed to generate hex for current theme. Colors might be dynamic or P3.")
        }
        
        if let metricsData = try? JSONEncoder().encode(visibleMetrics) {
            context["visibleMetrics"] = metricsData
        }
        
        if let themeData = try? JSONEncoder().encode(customTheme) {
            context["Breezy.customTheme"] = themeData
        }
        
        // Add specific raw values for enums
        context["Breezy.temperatureUnit"] = temperatureUnit.rawValue
        context["Breezy.windSpeedUnit"] = windSpeedUnit.rawValue
        context["Breezy.pressureUnit"] = pressureUnit.rawValue
        context["Breezy.visibilityUnit"] = visibilityUnit.rawValue
        context["Breezy.precipitationUnit"] = precipitationUnit.rawValue
        
        // Critical: Try to use sendMessage for INSTANT sync if reachable
        print("📱 PHONE: Attempting sync. Session State: \(session.activationState.rawValue), Reachable: \(session.isReachable)")
        
        if session.isReachable {
            print("📱 PHONE: Watch is reachable. Sending EXTRA fast message.")
            session.sendMessage(context, replyHandler: nil) { error in
                print("📱 PHONE: SendMessage failed: \(error.localizedDescription). Falling back to Complication UserInfo.")
                // Fallback 1: Complication User Info (Highest priority background transfer)
                self.session?.transferCurrentComplicationUserInfo(context)
            }
        } else {
            print("📱 PHONE: Watch NOT reachable. Queuing Complication User Info transfer.")
            session.transferCurrentComplicationUserInfo(context)
        }
        
        do {
            try session.updateApplicationContext(context)
            print("📱 PHONE: Application Context updated successfully.")
        } catch {
            print("❌ PHONE: Error updating watch context: \(error.localizedDescription)")
        }
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("📱 PHONE: Activation complete. State: \(activationState.rawValue), Paired: \(session.isPaired), WatchAppInstalled: \(session.isWatchAppInstalled)")
        if let error = error {
            print("WCSession activation failed: \(error.localizedDescription)")
        } else if activationState == .activated {
            // Trigger initial sync
            DispatchQueue.main.async {
                self.onSessionActivation?()
            }
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        // iOS specific - called when switching watches
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        // iOS specific - reactivate for new watch
        session.activate()
    }
    
    // MARK: - Message Handling
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        if message["request"] as? String == "weatherData" {
            print("📱 PHONE: Received weather request from Watch.")
            
            // We need to fetch weather.
            // If coords provided, use them. Else use current location (if available in a manager? or refuse?)
            // Ideally we'd have a shared LocationManager content. For now, let's assume the watch SENDS coordinates if it has them,
            // or the phone uses its last known location.
            
            Task {
                // 1. Determine Location
                var targetLocation: CLLocation?
                var targetCity: String = "Unknown Location"
                
                if let lat = message["latitude"] as? Double, let lon = message["longitude"] as? Double {
                    let loc = CLLocation(latitude: lat, longitude: lon)
                    targetLocation = loc
                    // Attempt reverse geocoding for city name if provided coords
                    if let placemarks = try? await CLGeocoder().reverseGeocodeLocation(loc),
                       let city = placemarks.first?.locality {
                        targetCity = city
                    }
                } else {
                    // Fallback: Use Phone's Location
                    print("📱 PHONE: Watch sent no coords. Requesting local location...")
                    do {
                        let locationData = try await self.locationHelper.requestLocationAndGetData()
                        targetLocation = CLLocation(latitude: locationData.latitude, longitude: locationData.longitude)
                        targetCity = locationData.city
                        print("📱 PHONE: Using Phone Location: \(locationData.city)")
                    } catch {
                        print("❌ PHONE: Failed to get local location: \(error.localizedDescription)")
                        replyHandler(["error": "Phone location unavailable: \(error.localizedDescription)"])
                        return
                    }
                }
                
                guard let location = targetLocation else {
                    replyHandler(["error": "No coordinates provided and fallback failed"])
                    return
                }
                
                // 2. Fetch Data
                do {
                    let formatting = WeatherFormattingContext(
                        temperatureUnit: .celsius,
                        windSpeedUnit: .metersPerSecond,
                        pressureUnit: .hectopascals,
                        visibilityUnit: .kilometers,
                        precipitationUnit: .millimeters
                    )
                    let locationData = LocationData(city: targetCity, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                    let result = try await WeatherProviderManager.shared.fetchWeather(for: locationData, formatting: formatting)
                    let weather = result.weather
                    
                    // 3. Serialize Data (Simple lightweight payload)
                    // We'll send the raw values needed for `WatchWeatherData`
                    var reply: [String: Any] = [:]
                    reply["city"] = targetCity // Send City Name
                    reply["weatherSource"] = WeatherProviderManager.shared.selectedSource.rawValue
                    reply["lat"] = location.coordinate.latitude
                    reply["lon"] = location.coordinate.longitude
                    reply["temp_c"] = parseCelsius(from: weather.temperature)
                    reply["feels_c"] = weather.feelsLike.flatMap(parseCelsius(from:))
                    reply["condition"] = weather.condition
                    reply["uv"] = weather.metrics?.uvIndex ?? 0
                    reply["wind_mps"] = parseWindMetersPerSecond(from: weather.metrics?.windSpeed)
                    reply["humidity"] = (weather.metrics?.humidity).map { Double($0) / 100.0 } ?? 0
                    reply["pressure_hpa"] = parsePressureHectopascals(from: weather.metrics?.pressure)
                    reply["visibility_km"] = parseVisibilityKilometers(from: weather.metrics?.visibility)
                    reply["cloud"] = parsePercentFraction(from: weather.metrics?.cloudCover)
                    reply["rainChance"] = parsePercentFraction(from: weather.metrics?.rainChance)
                    reply["high_c"] = weather.highTemp.flatMap(parseCelsius(from:))
                    reply["low_c"] = weather.lowTemp.flatMap(parseCelsius(from:))

                    if let sunrise = weather.dailyForecast.first?.sunriseDate {
                        reply["sunrise"] = sunrise.timeIntervalSince1970
                    }
                    if let sunset = weather.dailyForecast.first?.sunsetDate {
                        reply["sunset"] = sunset.timeIntervalSince1970
                    }

                    let hourlyData = (weather.allHourlyData ?? weather.hourlyForecast).prefix(24).map { h -> [String: Any] in
                        return [
                            "time": (h.sourceDate ?? Date()).timeIntervalSince1970,
                            "temp_c": temperatureUnitToCelsius(h.temperatureRaw, from: weather.temperature),
                            "condition": h.condition ?? weather.condition
                        ]
                    }
                    reply["hourly"] = hourlyData
                    
                    let dailyData = weather.dailyForecast.prefix(10).map { d -> [String: Any] in
                        return [
                            "time": DateFormatterHelper.dateFormatter.date(from: d.date)?.timeIntervalSince1970 ?? Date().timeIntervalSince1970,
                            "low_c": parseCelsius(from: d.lowTemp) ?? 0,
                            "high_c": parseCelsius(from: d.highTemp) ?? 0,
                            "condition": d.condition,
                            "rainChance": parsePercentFraction(from: d.chanceOfRain),
                            "uv": d.hourlyData.compactMap(\.uvIndex).max() ?? 0,
                            "wind_mps": parseWindMetersPerSecond(from: d.windSpeed),
                            "sunrise": d.sunriseDate?.timeIntervalSince1970 ?? 0,
                            "sunset": d.sunsetDate?.timeIntervalSince1970 ?? 0
                        ]
                    }
                    reply["daily"] = dailyData
                    
                    print("📱 PHONE: Sending weather reply to Watch.")
                    replyHandler(reply)
                    
                } catch {
                    print("📱 PHONE: Failed to fetch weather for Watch: \(error)")
                    replyHandler(["error": error.localizedDescription])
                }
            }
        }
    }

    private func parseCelsius(from formattedTemperature: String) -> Double? {
        let cleaned = formattedTemperature
            .replacingOccurrences(of: "°F", with: "")
            .replacingOccurrences(of: "°C", with: "")
            .replacingOccurrences(of: "°", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned) else { return nil }
        if formattedTemperature.contains("F") {
            return (value - 32.0) * 5.0 / 9.0
        }
        return value
    }

    private func temperatureUnitToCelsius(_ value: Double, from currentDisplay: String) -> Double {
        currentDisplay.contains("F") ? ((value - 32.0) * 5.0 / 9.0) : value
    }

    private func parseWindMetersPerSecond(from speed: String?) -> Double {
        guard let speed else { return 0 }
        let cleaned = speed.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        guard let value = Double(cleaned) else { return 0 }
        if speed.contains("km/h") {
            return value / 3.6
        }
        if speed.contains("mph") {
            return value / 2.23694
        }
        if speed.lowercased().contains("knot") || speed.lowercased().contains("kn") {
            return value / 1.94384
        }
        return value
    }

    private func parsePressureHectopascals(from pressure: String?) -> Double {
        guard let pressure else { return 0 }
        let cleaned = pressure.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        return Double(cleaned) ?? 0
    }

    private func parseVisibilityKilometers(from visibility: String?) -> Double {
        guard let visibility else { return 0 }
        let cleaned = visibility.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        guard let value = Double(cleaned) else { return 0 }
        return visibility.contains("mi") ? (value * 1.60934) : value
    }

    private func parsePercentFraction(from percentage: String?) -> Double {
        guard let percentage else { return 0 }
        let cleaned = percentage.replacingOccurrences(of: "%", with: "")
        guard let value = Double(cleaned) else { return 0 }
        return value / 100.0
    }
}
