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

    private var isMonitoring = false
    private let significantChangeThreshold: Double = 5000 // meters (5km - only update when moved to different weather zone)

    // Internal handler to bridge delegate to continuation safely
    private var continuationHandler: ((Result<LocationData, Error>) -> Void)?
    private var pendingLocationTimeoutWorkItem: DispatchWorkItem?
    private var awaitingAuthorizationForRequest = false
    private var pendingRequestTimeout: TimeInterval = 10

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

    // Thread-safe wrapper class
    private class ContinuationState {
        var continuation: CheckedContinuation<LocationData, Error>?
        var isResumed = false
        private let lock = NSLock()
        
        init(cont: CheckedContinuation<LocationData, Error>) {
            self.continuation = cont
        }
        
        @discardableResult
        func resume(with result: Result<LocationData, Error>) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !isResumed else { return false }
            isResumed = true
            
            switch result {
            case .success(let loc): continuation?.resume(returning: loc)
            case .failure(let err): continuation?.resume(throwing: err)
            }
            continuation = nil
            return true
        }
    }

    func requestLocationAndGetData(timeout: TimeInterval = 10) async throws -> LocationData {
        DispatchQueue.main.async { self.locationError = nil }
        
        pendingLocationTimeoutWorkItem?.cancel()
        pendingLocationTimeoutWorkItem = nil
        awaitingAuthorizationForRequest = false
        continuationHandler?(.failure(NSError(domain: "Location", code: 5, userInfo: [NSLocalizedDescriptionKey: "Cancelled by new request"])))
        
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            DispatchQueue.main.async {
                 self.locationError = "Breezy can't access your location. Please enable location access in Settings."
            }
            throw NSError(domain: "Location", code: 1, userInfo: [NSLocalizedDescriptionKey: "Location access denied"])
        }
        
        pendingRequestTimeout = timeout
        
        if status == .notDetermined {
           awaitingAuthorizationForRequest = true
           manager.requestWhenInUseAuthorization()
           // Timeout starts only after authorization is decided
        } else {
           manager.requestLocation()
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<LocationData, Error>) in
            let state = ContinuationState(cont: cont)
            
            self.continuationHandler = { [weak self] result in
                self?.pendingLocationTimeoutWorkItem?.cancel()
                self?.pendingLocationTimeoutWorkItem = nil
                self?.awaitingAuthorizationForRequest = false
                if state.resume(with: result) {
                    self?.continuationHandler = nil
                }
            }
            
            if status != .notDetermined {
                self.scheduleLocationRequestTimeout(timeout: timeout)
            }
        }
    }
    
    private func scheduleLocationRequestTimeout(timeout: TimeInterval) {
        pendingLocationTimeoutWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.continuationHandler?(.failure(NSError(domain: "Location", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out"])))
            DispatchQueue.main.async {
                self.locationError = "Location request timed out. Try again or choose a city manually."
            }
        }
        pendingLocationTimeoutWorkItem = work
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: work)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuationHandler?(.failure(error))
        
        DispatchQueue.main.async {
            self.locationError = "Breezy can't access your location. Please check that Location Access is allowed in Settings and try again."
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            if awaitingAuthorizationForRequest {
                awaitingAuthorizationForRequest = false
                manager.requestLocation()
                scheduleLocationRequestTimeout(timeout: pendingRequestTimeout)
            } else {
                manager.requestLocation()
            }
            if status == .authorizedAlways {
                startMonitoringSignificantLocationChanges()
            }
        } else if status == .denied || status == .restricted {
            stopMonitoringSignificantLocationChanges()
            awaitingAuthorizationForRequest = false
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
                updateLocation(from: loc, isSignificantChange: true)
                return
            }
        }
        
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
                    // Single published path; ContentView fetches from userLocation changes.
                    self.userLocation = locationData
                    self.continuationHandler?(.success(locationData))
                }
            } else {
                DispatchQueue.main.async {
                    self.locationError = "We couldn't find your city automatically. Try again or enter it below."
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
