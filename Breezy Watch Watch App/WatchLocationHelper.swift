//
//  WatchLocationHelper.swift
//  Breezy Watch Watch App
//
//  Location services for Watch app
//

import Foundation
import CoreLocation
import Combine

class WatchLocationHelper: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var userLocation: LocationData? = nil
    @Published var locationError: String? = nil
    
    private var continuation: CheckedContinuation<LocationData, Error>?
    private var timeoutTask: Task<Void, Never>?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    
    func requestLocationAndGetData(timeout: TimeInterval = 10) async throws -> LocationData {
        // Cancel any existing timeout task and resume any pending continuation
        await MainActor.run {
            if let oldCont = self.continuation {
                self.continuation = nil
                oldCont.resume(throwing: NSError(domain: "Location", code: 5, userInfo: [NSLocalizedDescriptionKey: "New location request started"]))
            }
            self.timeoutTask?.cancel()
            self.timeoutTask = nil
        }
        
        await MainActor.run { self.locationError = nil }
        let status = manager.authorizationStatus
        
        if status == .denied || status == .restricted {
            await MainActor.run {
                self.locationError = "Breezy can't access your location. Please enable location access in Settings."
            }
            throw NSError(domain: "Location", code: 1, userInfo: [NSLocalizedDescriptionKey: "Location access denied"])
        }
        
        if let existing = userLocation { return existing }
        
        // OPTIMIZATION: Check for fresh cached location (within 5 mins)
        if let lastLocation = manager.location, lastLocation.timestamp.timeIntervalSinceNow > -300 {
             return try await withCheckedThrowingContinuation { cont in
                Task { @MainActor in
                    self.continuation = cont
                    self.updateLocation(from: lastLocation)
                }
            }
        }
        
        // If not determined, request authorization first and wait
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
            
            // Wait for authorization dialog and user response (dialog appears on iPhone)
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Check status again
            let newStatus = manager.authorizationStatus
            
            if newStatus == .denied || newStatus == .restricted {
                await MainActor.run {
                    self.locationError = "Breezy can't access your location. Please enable location access in Settings."
                }
                throw NSError(domain: "Location", code: 1, userInfo: [NSLocalizedDescriptionKey: "Location access denied"])
            }
            
            // If still not determined, wait a bit more (user might be responding to dialog on iPhone)
            if newStatus == .notDetermined {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 more seconds
            }
        }
        
        // Ensure we have authorization before requesting location
        let finalAuthStatus = manager.authorizationStatus
        
        guard finalAuthStatus == .authorizedWhenInUse || finalAuthStatus == .authorizedAlways else {
            await MainActor.run {
                self.locationError = "Breezy can't access your location. Please enable location access in Settings."
            }
            throw NSError(domain: "Location", code: 1, userInfo: [NSLocalizedDescriptionKey: "Location access denied"])
        }
        
        manager.requestLocation()
        
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<LocationData, Error>) in
            Task { @MainActor in
                self.continuation = cont
                
                // Set up timeout task
                self.timeoutTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    
                    // Check if task was cancelled
                    if Task.isCancelled { return }
                    
                    await MainActor.run {
                        guard let self = self else { return }
                        if let cont = self.continuation {
                            self.continuation = nil
                            self.timeoutTask = nil
                            self.locationError = "Location request timed out."
                            cont.resume(throwing: NSError(domain: "Location", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out"]))
                        }
                    }
                }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.timeoutTask?.cancel()
            self.timeoutTask = nil
            self.locationError = "Breezy can't access your location. Please check that Location Access is allowed in Settings and try again."
            if let cont = self.continuation {
                self.continuation = nil
                cont.resume(throwing: error)
            }
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            // Only request location if we have a pending continuation
            if continuation != nil {
                manager.requestLocation()
            }
        } else if status == .denied || status == .restricted {
            Task { @MainActor in
                self.timeoutTask?.cancel()
                self.timeoutTask = nil
                self.locationError = "Breezy can't access your location. Please enable location access in Settings."
                if let cont = self.continuation {
                    self.continuation = nil
                    cont.resume(throwing: NSError(domain: "Location", code: 4, userInfo: [NSLocalizedDescriptionKey: "Authorization denied"]))
                }
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { return }
        updateLocation(from: loc)
    }
    
    private func updateLocation(from loc: CLLocation) {
        // Cancel timeout since we got location
        Task { @MainActor in
            self.timeoutTask?.cancel()
            self.timeoutTask = nil
        }
        
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, error in
            guard let self = self else { return }
            
            Task { @MainActor in
                // Always resume continuation, even if geocoding fails
                guard let cont = self.continuation else { return }
                self.continuation = nil
                
                // Handle geocoding error
                if let error = error {
                    self.locationError = "We couldn't find your city automatically. Try again."
                    cont.resume(throwing: NSError(domain: "Location", code: 3, userInfo: [NSLocalizedDescriptionKey: "Geocoding failed: \(error.localizedDescription)"]))
                    return
                }
                
                // Handle missing city
                guard let city = placemarks?.first?.locality else {
                    // Fallback: use coordinates if city not found
                    let locationData = LocationData(
                        city: "Unknown",
                        latitude: loc.coordinate.latitude,
                        longitude: loc.coordinate.longitude
                    )
                    self.userLocation = locationData
                    self.locationError = "We couldn't find your city automatically."
                    cont.resume(returning: locationData)
                    return
                }
                
                // Success case
                let locationData = LocationData(
                    city: city,
                    latitude: loc.coordinate.latitude,
                    longitude: loc.coordinate.longitude
                )
                self.userLocation = locationData
                cont.resume(returning: locationData)
            }
        }
    }
}

