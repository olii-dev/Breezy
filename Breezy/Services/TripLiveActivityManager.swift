//
//  TripLiveActivityManager.swift
//  Breezy
//
//  Live Activity ONLY while Go Now is active. Progress + ETA from GPS-lite snap.
//

import Foundation
import ActivityKit
import CoreLocation

enum TripLiveActivityStartResult {
    case started
    case disabled
    case failed(String)
}

@MainActor
final class TripLiveActivityManager {
    static let shared = TripLiveActivityManager()

    private var activity: Activity<TripActivityAttributes>?
    private var route: TripRouteOption?
    private var destinationName: String = ""
    private var originName: String = ""
    private var lastProgress: Double = 0
    private var routeAverageSpeed: Double = 13 // m/s fallback (~47 km/h)

    private init() {}

    var isActive: Bool { activity != nil }

    @discardableResult
    func start(trip: Trip, route: TripRouteOption, destinationName: String) -> TripLiveActivityStartResult {
        end()

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return .disabled
        }

        self.route = route
        self.destinationName = destinationName
        self.originName = trip.origin.name
        self.lastProgress = 0
        self.routeAverageSpeed = max(route.distanceMeters / max(route.expectedTravelTime, 1), 3)

        let state = makeState(
            route: route,
            snap: TripRouteGeometry.Snap(
                distanceAlong: 0,
                remaining: route.distanceMeters,
                progress: 0,
                crossTrackMeters: 0,
                coordinate: route.coordinates.first?.coordinate
                    ?? CLLocationCoordinate2D(latitude: trip.origin.latitude, longitude: trip.origin.longitude)
            ),
            location: nil
        )

        let attributes = TripActivityAttributes(
            originName: trip.origin.name,
            destinationName: destinationName
        )

        do {
            let arrival = Date().addingTimeInterval(route.expectedTravelTime)
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: arrival.addingTimeInterval(3600)),
                pushType: nil
            )
            publishSnapshot(from: state)
            TripGoNowTracker.shared.start(route: route) { [weak self] location in
                self?.handleLocation(location)
            }
            pushState(state)
            return .started
        } catch {
            activity = nil
            return .failed(error.localizedDescription)
        }
    }

    func end() {
        TripGoNowTracker.shared.stop()
        route = nil
        lastProgress = 0
        let current = activity
        activity = nil
        TripStore.clearGoNowSnapshot()
        guard let current else { return }
        Task {
            let final = current.content.state
            await current.end(
                .init(state: final, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
    }

    private func handleLocation(_ location: CLLocation) {
        guard let route, activity != nil else { return }
        let snap = TripGoNowTracker.progress(along: route, location: location)

        // Ignore noisy snaps far off-route.
        guard snap.crossTrackMeters < 1_200 else { return }

        let progress = max(lastProgress, snap.progress)
        lastProgress = progress
        var adjusted = snap
        adjusted.progress = progress
        adjusted.remaining = max(0, route.distanceMeters * (1 - progress))
        adjusted.distanceAlong = route.distanceMeters - adjusted.remaining

        let state = makeState(route: route, snap: adjusted, location: location)
        pushState(state)
        publishSnapshot(from: state)

        // End only when clearly near the destination on-route.
        if progress >= 0.97, adjusted.remaining < 500, snap.crossTrackMeters < 250 {
            end()
        }
    }

    private func pushState(_ state: TripActivityAttributes.ContentState) {
        guard let activity else { return }
        let stale = Date().addingTimeInterval(TimeInterval(max(state.minutesToArrival, 15) * 60 + 600))
        Task {
            await activity.update(.init(state: state, staleDate: stale))
        }
    }

    private func makeState(
        route: TripRouteOption,
        snap: TripRouteGeometry.Snap,
        location: CLLocation?
    ) -> TripActivityAttributes.ContentState {
        let speed = liveSpeedMetersPerSecond(location: location, route: route)
        let etaSeconds = snap.remaining / max(speed, 1)
        let arrival = Date().addingTimeInterval(etaSeconds)
        let minutes = max(0, Int(ceil(etaSeconds / 60)))

        let ahead = TripGoNowTracker.aheadSample(on: route, distanceAlong: snap.distanceAlong)
        let weather = ahead?.weather ?? route.samples.last?.weather
        let offline = !TripNetworkMonitor.shared.isOnline

        return TripActivityAttributes.ContentState(
            destinationName: destinationName,
            etaText: Self.etaFormatter.string(from: arrival),
            minutesToArrival: minutes,
            condition: weather?.condition ?? "En route",
            temperatureText: weather?.formattedTemperature ?? "--°",
            progress: snap.progress,
            nextAlert: aheadHint(route: route, distanceAlong: snap.distanceAlong, speed: speed),
            aheadPlaceLabel: ahead?.placeLabel,
            distanceRemainingText: remainingText(snap.remaining),
            isOffline: offline
        )
    }

    /// Prefer GPS speed when valid; otherwise route average.
    private func liveSpeedMetersPerSecond(location: CLLocation?, route: TripRouteOption) -> Double {
        if let location, location.speed >= 1.5 {
            // speedAccuracy < 0 means “unknown” on some builds — still usable if speed itself is plausible.
            if location.speedAccuracy < 0 || location.speedAccuracy <= 8 {
                return location.speed
            }
        }
        return routeAverageSpeed
    }

    private func aheadHint(route: TripRouteOption, distanceAlong: Double, speed: Double) -> String? {
        let upcoming = route.samples.filter {
            $0.distanceFromStartMeters >= distanceAlong + 500
                && (!$0.riskFlags.isEmpty || ($0.weather?.precipitationProbability ?? 0) >= 0.5)
        }
        guard let next = upcoming.first else { return nil }
        let remainingDrive = max(500, next.distanceFromStartMeters - distanceAlong)
        let minutes = max(1, Int((remainingDrive / max(speed, 1)) / 60))
        if let flag = next.riskFlags.first {
            return "\(flag.title) in ~\(minutes) min"
        }
        if let weather = next.weather {
            return "\(weather.condition) in ~\(minutes) min"
        }
        return nil
    }

    private func remainingText(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.0f km left", meters / 1000)
        }
        return String(format: "%.0f m left", meters)
    }

    private func publishSnapshot(from state: TripActivityAttributes.ContentState) {
        TripStore.goNowSnapshot = TripGoNowSnapshot(
            isActive: true,
            originName: originName,
            destinationName: state.destinationName,
            etaText: state.etaText,
            condition: state.condition,
            temperatureText: state.temperatureText,
            progress: state.progress,
            nextAlert: state.nextAlert,
            aheadPlaceLabel: state.aheadPlaceLabel,
            distanceRemainingText: state.distanceRemainingText,
            isOffline: state.isOffline,
            updatedAt: Date()
        )
    }

    private static let etaFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
