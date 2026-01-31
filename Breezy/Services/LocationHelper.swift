//
//  LocationHelper.swift
//  Breezy
//
//  Location services wrapper
//

import Foundation
import CoreLocation
import Combine

class LocationHelper: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var userLocation: LocationData? = nil
    @Published var locationError: String? = nil
    @Published var significantLocationChange: LocationData? = nil

    private var continuation: CheckedContinuation<LocationData, Error>?
    private var isMonitoring = false
    private let significantChangeThreshold: Double = 1000 // meters

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    
    func startMonitoringSignificantLocationChanges() {
        guard !isMonitoring else { return }
        isMonitoring = true
        manager.startMonitoringSignificantLocationChanges()
    }
    
    func stopMonitoringSignificantLocationChanges() {
        guard isMonitoring else { return }
        isMonitoring = false
        manager.stopMonitoringSignificantLocationChanges()
    }

    // Internal handler to bridge delegate to continuation safely
    private var continuationHandler: ((Result<LocationData, Error>) -> Void)?
    
    // Thread-safe wrapper class
    private class ContinuationState {
        var continuation: CheckedContinuation<LocationData, Error>?
        var isResumed = false
        private let lock = NSLock()
        
        init(cont: CheckedContinuation<LocationData, Error>) {
            self.continuation = cont
        }
        
        func resume(with result: Result<LocationData, Error>) {
            lock.lock()
            defer { lock.unlock() }
            guard !isResumed else { return }
            isResumed = true
            
            switch result {
            case .success(let loc): continuation?.resume(returning: loc)
            case .failure(let err): continuation?.resume(throwing: err)
            }
            continuation = nil
        }
    }

    func requestLocationAndGetData(timeout: TimeInterval = 10) async throws -> LocationData {
        DispatchQueue.main.async { self.locationError = nil }
        
        // Cancel existing if needed (though simplistic here)
        continuationHandler?(.failure(NSError(domain: "Location", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cancelled by new request"])))
        
        // Check auth inline first
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            DispatchQueue.main.async {
                 self.locationError = "Breezy can't access your location. Please enable location access in Settings."
            }
            throw NSError(domain: "Location", code: 1, userInfo: [NSLocalizedDescriptionKey: "Location access denied"])
        }
        
        if status == .notDetermined {
           manager.requestWhenInUseAuthorization()
           // We continue, relying on delegate to trigger location update once authorized
        } else {
           manager.requestLocation()
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<LocationData, Error>) in
            let state = ContinuationState(cont: cont)
            
            // Set up handler
            self.continuationHandler = { result in
                state.resume(with: result)
            }
            
            // Timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                // Determine if we should fail or if it completed
                self.continuationHandler?(.failure(NSError(domain: "Location", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out"])))
                
                 DispatchQueue.main.async {
                     // Only update UI error if we actually timed out (state check handled in resume)
                     // But strictly, we can't check state here easily without exposing it.
                     // It's benign to set error if we think we failed.
                 }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Resume continuation if active
        continuationHandler?(.failure(error))
        
        DispatchQueue.main.async {
            self.locationError = "Breezy can't access your location. Please check that Location Access is allowed in Settings and try again."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
            if status == .authorizedAlways {
                startMonitoringSignificantLocationChanges()
            }
        } else if status == .denied || status == .restricted {
            stopMonitoringSignificantLocationChanges()
            continuationHandler?(.failure(NSError(domain: "Location", code: 4, userInfo: [NSLocalizedDescriptionKey: "Authorization denied"])))
            
            DispatchQueue.main.async {
                self.locationError = "Breezy can't access your location. Please enable location access in Settings."
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { return }
        
        // Check if this is a significant location change
        if let previousLocation = userLocation {
            let previousCLLocation = CLLocation(latitude: previousLocation.latitude, longitude: previousLocation.longitude)
            let distance = loc.distance(from: previousCLLocation)
            
            if distance > significantChangeThreshold {
                // Significant location change detected
                updateLocation(from: loc, isSignificantChange: true)
                return
            }
        }
        
        // Regular location update
        updateLocation(from: loc, isSignificantChange: false)
    }
    
    private func updateLocation(from loc: CLLocation, isSignificantChange: Bool) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(loc) { placemarks, error in
            if let city = placemarks?.first?.locality {
                let locationData = LocationData(
                    city: city,
                    latitude: loc.coordinate.latitude,
                    longitude: loc.coordinate.longitude
                )
                DispatchQueue.main.async {
                    if isSignificantChange {
                        self.significantLocationChange = locationData
                    }
                    self.userLocation = locationData
                    // Resume continuation if active
                    self.continuationHandler?(.success(locationData))
                }
            } else {
                DispatchQueue.main.async {
                    self.locationError = "We couldn't find your city automatically. Try again or enter it below."
                     // Resume continuation if active
                     self.continuationHandler?(.failure(NSError(domain: "Location", code: 3, userInfo: [NSLocalizedDescriptionKey: "No city found"])))
                }
            }
        }
    }
    
    func getCoordinates(for cityName: String) async throws -> LocationData {
        let geocoder = CLGeocoder()
        
        return try await withCheckedThrowingContinuation { continuation in
            geocoder.geocodeAddressString(cityName) { placemarks, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let placemark = placemarks?.first,
                      let location = placemark.location else {
                    continuation.resume(throwing: NSError(domain: "Geocoding", code: 1, userInfo: [NSLocalizedDescriptionKey: "Location not found"]))
                    return
                }
                
                let city = placemark.locality ?? cityName
                let locationData = LocationData(
                    city: city,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                )
                continuation.resume(returning: locationData)
            }
        }
    }
}

