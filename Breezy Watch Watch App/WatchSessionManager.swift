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
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("WCSession activation failed: \(error.localizedDescription)")
        }
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        DispatchQueue.main.async {
            let defaults = UserDefaults.standard
            
            if let useMinimalistIcons = applicationContext["useMinimalistIcons"] as? Bool {
                defaults.set(useMinimalistIcons, forKey: "Breezy.useMinimalistIcons")
            }
            
            if let tempRaw = applicationContext["Breezy.temperatureUnit"] as? String {
                defaults.set(tempRaw, forKey: "Breezy.temperatureUnit")
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
