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
import WeatherKit

class WatchSessionManager: NSObject, WCSessionDelegate, ObservableObject {
    static let shared = WatchSessionManager()
    
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
        useMinimalistIcons: Bool,
        typography: WeatherFont,
        visibleMetrics: Set<WeatherMetric>,
        temperatureUnit: TemperatureUnit,
        windSpeedUnit: WindSpeedUnit,
        pressureUnit: PressureUnit,
        visibilityUnit: VisibilityUnit,
        themeMode: WeatherViewModel.ThemeMode,
        presetTheme: String,
        currentTheme: WeatherTheme,
        customTheme: WeatherTheme,
        mapStyle: WeatherViewModel.RadarMapStyle
    ) {
        guard let session = session, session.activationState == .activated else { return }
        
        var context: [String: Any] = [
            "useMinimalistIcons": useMinimalistIcons,
            "typography": typography.rawValue,
            "Breezy.temperatureUnit": temperatureUnit.rawValue,
            "Breezy.windSpeedUnit": windSpeedUnit.rawValue,
            "Breezy.pressureUnit": pressureUnit.displayName, // ID is rawValue
            "Breezy.visibilityUnit": visibilityUnit.rawValue,
            "Breezy.themeMode": themeMode.rawValue,
            "Breezy.presetTheme": presetTheme,
            "Breezy.mapStyle": mapStyle.rawValue
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
                
                if let lat = message["latitude"] as? Double, let lon = message["longitude"] as? Double {
                    targetLocation = CLLocation(latitude: lat, longitude: lon)
                } else {
                    // Fallback to saved location or current location manager
                    // This is a bit tricky since we're in a utility class.
                    // For now, let's reply with error if no coords provided, forcing Watch to use its own GPS.
                    // Or keep it simple: Hybrid mode assumes Watch HAS a location (from GPS) and just wants the DATA download to happen on Phone.
                }
                
                guard let location = targetLocation else {
                    replyHandler(["error": "No coordinates provided"])
                    return
                }
                
                // 2. Fetch Data
                do {
                    let service = WeatherService.shared
                    let weather = try await service.weather(for: location)
                    
                    // 3. Serialize Data (Simple lightweight payload)
                    // We'll send the raw values needed for `WatchWeatherData`
                    
                    let current = weather.currentWeather
                    let daily = weather.dailyForecast.first
                    
                    var reply: [String: Any] = [:]
                    
                    // Units (Send raw values, Watch handles conversion/display based on its prefs)
                    // Actually, easier to send standardized values (Celsius/Metric) and let Watch convert.
                    
                    reply["temp_c"] = current.temperature.converted(to: .celsius).value
                    reply["feels_c"] = current.apparentTemperature.converted(to: .celsius).value
                    reply["condition"] = current.condition.description
                    reply["uv"] = current.uvIndex.value
                    reply["wind_mps"] = current.wind.speed.converted(to: .metersPerSecond).value
                    reply["humidity"] = current.humidity
                    reply["pressure_hpa"] = current.pressure.converted(to: .hectopascals).value
                    reply["visibility_km"] = current.visibility.converted(to: .kilometers).value
                    reply["dew_c"] = current.dewPoint.converted(to: .celsius).value
                    reply["cloud"] = current.cloudCover
                    
                    if let d = daily {
                        reply["high_c"] = d.highTemperature.converted(to: .celsius).value
                        reply["low_c"] = d.lowTemperature.converted(to: .celsius).value
                        reply["rainChance"] = d.precipitationChance
                        reply["sunrise"] = d.sun.sunrise?.timeIntervalSince1970
                        reply["sunset"] = d.sun.sunset?.timeIntervalSince1970
                    }
                    
                    // Minimal Hourly (Next 24h)
                    let hourlyData = weather.hourlyForecast.prefix(24).map { h -> [String: Any] in
                        return [
                            "time": h.date.timeIntervalSince1970,
                            "temp_c": h.temperature.converted(to: .celsius).value,
                            "condition": h.condition.description
                        ]
                    }
                    reply["hourly"] = hourlyData
                    
                    print("📱 PHONE: Sending weather reply to Watch.")
                    replyHandler(reply)
                    
                } catch {
                    print("📱 PHONE: Failed to fetch weather for Watch: \(error)")
                    replyHandler(["error": error.localizedDescription])
                }
            }
        }
    }
}
