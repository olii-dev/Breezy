//
//  WatchSessionManager.swift
//  Breezy Watch Watch App
//
//  Manages Watch Connectivity on WatchOS
//

import Foundation
import WatchConnectivity
import CoreLocation

class WatchSessionManager: NSObject, WCSessionDelegate {
    static let shared = WatchSessionManager()
    
    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    
    private override init() {
        super.init()
        session?.delegate = self
        session?.activate()
    }
    
    func startSession() {
        if session?.activationState != .activated {
            session?.activate()
        }
    }

    /// True when the paired iPhone is connected and answerable — the watch
    /// defers its own alerts in that case (the phone's notifications mirror).
    var isPhoneReachable: Bool {
        session?.activationState == .activated && session?.isReachable == true
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async {
            // Watch-local mirror, consistent with the watch's own settings writes.
            let defaults = UserDefaults(suiteName: WatchAppStorageKey.appGroup) ?? .standard

            if let useMinimalistIcons = applicationContext["useMinimalistIcons"] as? Bool {
                defaults.set(useMinimalistIcons, forKey: "Breezy.useMinimalistIcons")
            }

            if let tempRaw = applicationContext["Breezy.temperatureUnit"] as? String {
                // The phone pushes "Celsius"/"Fahrenheit" rawValues; the watch's
                // TemperatureUnit uses lowercase — normalize or the value never parses.
                let normalized = tempRaw.lowercased()
                let mapped = normalized == "fahrenheit" || normalized == "f" ? "fahrenheit" : "celsius"
                defaults.set(mapped, forKey: "Breezy.temperatureUnit")
            }

            if let windRaw = applicationContext["Breezy.windSpeedUnit"] as? String {
                defaults.set(windRaw, forKey: "Breezy.windSpeedUnit")
            }

            if let pressureRaw = applicationContext["Breezy.pressureUnit"] as? String {
                defaults.set(pressureRaw, forKey: "Breezy.pressureUnit")
            }

            if let visRaw = applicationContext["Breezy.visibilityUnit"] as? String {
                defaults.set(visRaw, forKey: "Breezy.visibilityUnit")
            }

            if let precipRaw = applicationContext["Breezy.precipitationUnit"] as? String {
                defaults.set(precipRaw, forKey: "Breezy.precipitationUnit")
            }

            // Forwarded notification preferences (used by WatchNotificationManager).
            if let forecastHour = applicationContext["Breezy.dailyForecastHour"] as? Int {
                defaults.set(forecastHour, forKey: "WatchPhoneForecastHour")
            }
            if let forecastMinute = applicationContext["Breezy.dailyForecastMinute"] as? Int {
                defaults.set(forecastMinute, forKey: "WatchPhoneForecastMinute")
            }

            // Stargazing payload (aurora + golden hour) for the watch page.
            WatchAuroraStore.apply(context: applicationContext)

            // Notify view model to reload
            NotificationCenter.default.post(name: NSNotification.Name("WatchContextUpdated"), object: nil)
            NotificationCenter.default.post(name: NSNotification.Name("WatchTemperatureUnitChanged"), object: nil)
        }
    }

    // MARK: - Weather Data Requests
    
    /// Requests the latest weather data from the paired iPhone.
    /// Returns the weather data if successful, or nil if the phone is unreachable/fails.
    func requestWeatherData(for coordinate: CLLocationCoordinate2D? = nil) async throws -> [String: Any]? {
        guard let session = session, session.activationState == .activated, session.isReachable else {
            throw NSError(domain: "WatchConnectivity", code: 1, userInfo: [NSLocalizedDescriptionKey: "Session not reachable"])
        }
        
        var message: [String: Any] = ["request": "weatherData"]
        if let coordinate = coordinate {
            message["latitude"] = coordinate.latitude
            message["longitude"] = coordinate.longitude
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(message, replyHandler: { reply in
                continuation.resume(returning: reply)
            }, errorHandler: { error in
                continuation.resume(throwing: error)
            })
        }
    }
}
