//
//  WatchLocationTypes.swift
//  Breezy Watch Watch App
//
//  Created for compatibility and to fix scope issues in the Watch target.
//

import Foundation
import CoreLocation

/// Represents a location saved or recently searched for on the Watch.
struct WatchSavedLocation: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    
    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// A simplified location helper for the Watch App that resolves the current location.
class WatchLocationHelper: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<LocationData, Error>?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    
    /// Requests the current GPS location and reverse geocodes it to find the city.
    func requestLocationAndGetData(timeout: TimeInterval = 10) async throws -> LocationData {
        let status = manager.authorizationStatus
        
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            manager.requestLocation()
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            let city = placemarks?.first?.locality ?? "Current Location"
            let data = LocationData(city: city, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            
            self?.continuation?.resume(returning: data)
            self?.continuation = nil
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
