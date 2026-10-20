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
    private var lastLocation: CLLocation?
    private var consecutiveOffRouteFixes = 0
    private var lastWeatherRefreshAt: Date?

    private init() {}

    var isActive: Bool { activity != nil }

    @discardableResult
    func start(trip: Trip, route: TripRouteOption, destinationName: String) -> TripLiveActivityStartResult {
        end()

        self.route = route
        self.destinationName = destinationName
        self.originName = trip.origin.name
        self.lastProgress = 0
        self.routeAverageSpeed = max(route.distanceMeters / max(route.expectedTravelTime, 1), 3)
        self.lastLocation = nil
        self.consecutiveOffRouteFixes = 0
        self.lastWeatherRefreshAt = nil

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

        // Trip tracking (snapshot, widget, alerts) runs regardless of whether
        // the Live Activity itself can be shown.
        TripStore.goNowRoute = route
        TripStore.goNowStartedAt = Date()
        publishSnapshot(from: state)
        TripGoNowTracker.shared.start(route: route) { [weak self] location in
            self?.handleLocation(location)
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return .disabled
        }

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
            pushState(state)
            return .started
        } catch {
            activity = nil
            return .failed(error.localizedDescription)
        }
    }

    /// Re-adopt a trip that outlived the process: the system-owned activity
    /// plus the persisted route/snapshot. Restarts tracking. Stale orphans
    /// (activity with no fresh trip state) are dismissed.
    func restore() {
        guard activity == nil else { return }

        let adopted = Activity<TripActivityAttributes>.activities.first { $0.activityState == .active }

        guard TripStore.isGoNowActive(), let route = TripStore.goNowRoute else {
            if let adopted {
                activity = adopted
                end()
            } else {
                TripStore.clearGoNowSnapshot()
            }
            return
        }

        let snapshot = TripStore.goNowSnapshot
        activity = adopted
        self.route = route
        self.destinationName = adopted?.attributes.destinationName ?? snapshot.destinationName
        self.originName = adopted?.attributes.originName ?? snapshot.originName
        self.lastProgress = snapshot.progress
        self.routeAverageSpeed = max(route.distanceMeters / max(route.expectedTravelTime, 1), 3)
        self.lastLocation = nil
        self.consecutiveOffRouteFixes = 0
        self.lastWeatherRefreshAt = nil
        TripGoNowTracker.shared.start(route: route) { [weak self] location in
            self?.handleLocation(location)
        }
    }

    func end() {
        TripGoNowTracker.shared.stop()
        route = nil
        lastProgress = 0
        lastLocation = nil
        consecutiveOffRouteFixes = 0
        lastWeatherRefreshAt = nil
        // Sweep every active activity of this type — a held-reference-only end
        // would leave strays behind if restore ever missed one.
        let strays = Activity<TripActivityAttributes>.activities.filter { $0.activityState == .active }
        activity = nil
        TripStore.clearGoNowSnapshot()
        guard !strays.isEmpty else { return }
        Task {
            for current in strays {
                let final = current.content.state
                await current.end(
                    .init(state: final, staleDate: nil),
                    dismissalPolicy: .immediate
                )
            }
        }
    }

    private func handleLocation(_ location: CLLocation) {
        // Tracking continues even when the Live Activity handle is absent
        // (e.g. LAs disabled mid-trip) so the snapshot and widget stay live.
        guard let route else { return }
        let snap = TripGoNowTracker.progress(along: route, location: location)

        // Far off-route (detour, tunnel exit, GPS drift): don't freeze silently
        // — after a few far fixes flag the state and keep the last good
        // progress until a fix snaps back onto the route.
        guard snap.crossTrackMeters < 1_200 else {
            consecutiveOffRouteFixes += 1
            if consecutiveOffRouteFixes >= 3 {
                pushCurrentState()
            }
            return
        }
        consecutiveOffRouteFixes = 0
        lastLocation = location

        let progress = max(lastProgress, snap.progress)
        lastProgress = progress
        var adjusted = snap
        adjusted.progress = progress
        adjusted.remaining = max(0, route.distanceMeters * (1 - progress))
        adjusted.distanceAlong = route.distanceMeters - adjusted.remaining

        let state = makeState(route: route, snap: adjusted, location: location)
        pushState(state)
        publishSnapshot(from: state)

        maybeRefreshUpcomingWeather(distanceAlong: adjusted.distanceAlong)

        // End only when clearly near the destination on-route.
        if progress >= 0.97, adjusted.remaining < 500, snap.crossTrackMeters < 250 {
            end()
        }
    }

    /// Re-push the current state (used when only flags like off-route change).
    private func pushCurrentState() {
        guard let route else { return }
        let remaining = max(0, route.distanceMeters * (1 - lastProgress))
        let snap = TripRouteGeometry.Snap(
            distanceAlong: route.distanceMeters - remaining,
            remaining: remaining,
            progress: lastProgress,
            crossTrackMeters: 1_200, // forces the off-route flag in makeState
            coordinate: lastLocation?.coordinate ?? route.coordinates.first?.coordinate
                ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        )
        let state = makeState(route: route, snap: snap, location: lastLocation)
        pushState(state)
        publishSnapshot(from: state)
    }

    /// Weather along the road goes stale on long drives — re-fetch the
    /// upcoming samples at most every 15 minutes of driving.
    private func maybeRefreshUpcomingWeather(distanceAlong: Double) {
        guard let route else { return }
        let now = Date()
        guard lastWeatherRefreshAt.map({ now.timeIntervalSince($0) >= 15 * 60 }) ?? true else { return }
        guard route.distanceMeters * (1 - lastProgress) > 20_000 else { return }

        lastWeatherRefreshAt = now
        let upcoming = route.samples.filter { $0.distanceFromStartMeters >= distanceAlong }
        guard !upcoming.isEmpty else { return }

        Task { [weak self] in
            let refreshed = await TripWeatherService.shared.enrichSamples(upcoming)
            guard !refreshed.isEmpty else { return }
            await MainActor.run { [weak self] in
                guard let self, var currentRoute = self.route else { return }
                let byID = Dictionary(uniqueKeysWithValues: refreshed.map { ($0.id, $0) })
                currentRoute.samples = currentRoute.samples.map { byID[$0.id] ?? $0 }
                self.route = currentRoute
                self.pushCurrentState()
            }
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
        let hero = aheadHero(route: route, distanceAlong: snap.distanceAlong, speed: speed)
        let isOffRoute = snap.crossTrackMeters >= 1_200

        return TripActivityAttributes.ContentState(
            destinationName: destinationName,
            etaText: Self.etaFormatter.string(from: arrival),
            minutesToArrival: minutes,
            arrival: arrival,
            condition: weather?.condition ?? "En route",
            temperatureText: weather?.formattedTemperature ?? "--°",
            progress: snap.progress,
            nextAlert: hero.map { "\($0.text) in ~\($0.minutes) min" },
            aheadPlaceLabel: ahead?.placeLabel,
            distanceRemainingText: remainingText(snap.remaining),
            weatherAheadText: hero?.text,
            weatherAheadMinutes: hero?.minutes,
            weatherAheadSymbolName: hero?.symbolName,
            isOffline: offline,
            isOffRoute: isOffRoute
        )
    }

    private struct AheadHero {
        let text: String
        let minutes: Int
        let symbolName: String
    }

    /// The next stretch of road worth warning about (risk flag or likely
    /// precipitation), split into parts the widget can lay out as a hero row.
    private func aheadHero(route: TripRouteOption, distanceAlong: Double, speed: Double) -> AheadHero? {
        let upcoming = route.samples.filter {
            $0.distanceFromStartMeters >= distanceAlong + 500
                && (!$0.riskFlags.isEmpty || ($0.weather?.precipitationProbability ?? 0) >= 0.5)
        }
        guard let next = upcoming.first else { return nil }
        let remainingDrive = max(500, next.distanceFromStartMeters - distanceAlong)
        let minutes = max(1, Int((remainingDrive / max(speed, 1)) / 60))
        let place = next.placeLabel.isEmpty ? "" : " near \(next.placeLabel)"

        if let flag = next.riskFlags.first {
            return AheadHero(text: "\(flag.title)\(place)", minutes: minutes, symbolName: flag.systemImage)
        }
        if let weather = next.weather {
            return AheadHero(
                text: "\(weather.condition)\(place)",
                minutes: minutes,
                symbolName: TripWeatherSnapshot.symbolName(for: weather.condition)
            )
        }
        return nil
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
            updatedAt: Date(),
            arrival: state.arrival,
            weatherAheadText: state.weatherAheadText,
            weatherAheadMinutes: state.weatherAheadMinutes,
            weatherAheadSymbolName: state.weatherAheadSymbolName,
            isOffRoute: state.isOffRoute
        )
    }

    private static let etaFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
