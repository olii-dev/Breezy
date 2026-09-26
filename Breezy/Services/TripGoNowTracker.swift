//
//  TripGoNowTracker.swift
//  Breezy
//
//  GPS-lite tracking while Go Now is active — significant / coarse updates only.
//

import Foundation
import CoreLocation

@MainActor
final class TripGoNowTracker: NSObject, CLLocationManagerDelegate {
    static let shared = TripGoNowTracker()

    private let manager = CLLocationManager()
    private var route: TripRouteOption?
    private var onUpdate: ((CLLocation) -> Void)?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 750 // GPS-lite: ~0.75 km between updates
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .automotiveNavigation
        manager.allowsBackgroundLocationUpdates = false
    }

    func start(route: TripRouteOption, onUpdate: @escaping (CLLocation) -> Void) {
        self.route = route
        self.onUpdate = onUpdate

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            beginUpdates()
        default:
            break
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        route = nil
        onUpdate = nil
    }

    /// Progress along route via true polyline projection.
    static func progress(along route: TripRouteOption, location: CLLocation) -> TripRouteGeometry.Snap {
        TripRouteGeometry.snap(location: location, onto: route)
    }

    static func aheadSample(on route: TripRouteOption, distanceAlong: Double) -> TripSamplePoint? {
        let ahead = route.samples.first { $0.distanceFromStartMeters >= distanceAlong + 500 }
        return ahead ?? route.samples.last
    }

    private func beginUpdates() {
        // Prefer significant-change; coarse updatingLocation as a light supplement.
        manager.startMonitoringSignificantLocationChanges()
        manager.startUpdatingLocation()
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                if self.route != nil { self.beginUpdates() }
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.onUpdate?(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep last known progress; GPS-lite may fail intermittently.
    }
}
