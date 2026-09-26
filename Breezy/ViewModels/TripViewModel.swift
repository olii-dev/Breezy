//
//  TripViewModel.swift
//  Breezy
//
//  On the Way state — planning, departure scrub, stops, routes, Go Now.
//

import Foundation
import SwiftUI
import Combine
import CoreLocation

@MainActor
final class TripViewModel: ObservableObject {
    // MARK: - Setup

    @Published var origin: TripEndpoint?
    @Published var destination: TripEndpoint?
    @Published var stops: [TripStop] = []
    @Published var departure: Date = Date()

    // MARK: - Results

    @Published var routes: [TripRouteOption] = []
    @Published var selectedRouteID: UUID?
    @Published var arrivalBrief: String = ""
    @Published var isLoadingRoute = false
    @Published var isLoadingWeather = false
    @Published var errorMessage: String?
    @Published var recentTrips: [Trip] = []
    @Published var needsWeatherRefreshHint = false

    // MARK: - Live

    @Published var isTripLive = false
    @Published var goNowError: String?

    private let routeService = TripRouteService.shared
    private var departureDebounceTask: Task<Void, Never>?
    private var weatherGeneration = 0
    private var activeTripID: UUID?

    var selectedRoute: TripRouteOption? {
        if let selectedRouteID {
            return routes.first { $0.id == selectedRouteID } ?? routes.first
        }
        return routes.first
    }

    var isOnline: Bool { TripNetworkMonitor.shared.isOnline }

    var maxDeparture: Date {
        Calendar.current.date(byAdding: .day, value: 16, to: Date()) ?? Date().addingTimeInterval(16 * 86_400)
    }

    var departureRange: ClosedRange<Date> {
        Date()...maxDeparture
    }

    init() {
        reloadRecent()
        // Warm network monitor.
        _ = TripNetworkMonitor.shared
    }

    // MARK: - Endpoints

    func useCurrentLocation(asOrigin: Bool, locationHelper: LocationHelper, fallbackCity: String?) {
        guard let location = locationHelper.userLocation else {
            errorMessage = "Current location unavailable. Enable location access and try again."
            return
        }
        let name = (fallbackCity?.isEmpty == false ? fallbackCity! : location.city)
        let endpoint = TripEndpoint(name: name, latitude: location.latitude, longitude: location.longitude)
        if asOrigin {
            origin = endpoint
        } else {
            destination = endpoint
        }
    }

    func setEndpoint(_ location: LocationData, asOrigin: Bool) {
        let endpoint = TripEndpoint(location: location)
        if asOrigin {
            origin = endpoint
        } else {
            destination = endpoint
        }
    }

    func addStop(_ location: LocationData, dwellMinutes: Int = 15) {
        let stop = TripStop(endpoint: TripEndpoint(location: location), dwellMinutes: dwellMinutes)
        stops.append(stop)
    }

    func removeStop(_ stop: TripStop) {
        stops.removeAll { $0.id == stop.id }
        stopsChangedReplan()
    }

    func updateDwell(for stopID: UUID, minutes: Int) {
        guard let index = stops.firstIndex(where: { $0.id == stopID }) else { return }
        stops[index].dwellMinutes = max(0, minutes)
        stopsChangedReplan()
    }

    func reorderStops(from source: IndexSet, to destination: Int) {
        stops.move(fromOffsets: source, toOffset: destination)
        stopsChangedReplan()
    }

    // MARK: - Planning

    func planRoute() {
        Task { await planRouteAsync() }
    }

    func planRouteAsync() async {
        guard let origin, let destination else {
            errorMessage = TripRouteError.missingEndpoints.localizedDescription
            return
        }

        guard isOnline else {
            errorMessage = "Connect to the internet to plan a new route. Cached trips still work offline."
            return
        }

        isLoadingRoute = true
        isLoadingWeather = false
        errorMessage = nil
        arrivalBrief = ""
        needsWeatherRefreshHint = false

        do {
            let options = try await routeService.fetchRouteOptions(
                origin: origin,
                destination: destination,
                stops: stops,
                departure: departure,
                includeAlternates: stops.isEmpty
            )
            routes = options
            selectedRouteID = options.first?.id
            isLoadingRoute = false
            await enrichAllRoutesWeather()
            persistCurrentTrip()
        } catch {
            isLoadingRoute = false
            errorMessage = error.localizedDescription
        }
    }

    func selectRoute(_ id: UUID) {
        selectedRouteID = id
        if let route = selectedRoute {
            arrivalBrief = TripWeatherService.shared.arrivalBrief(
                for: route.samples,
                destinationName: destination?.name ?? "destination"
            )
        }
        persistCurrentTrip()
    }

    /// Departure slider / picker — single source of truth.
    func departureChanged(_ newValue: Date) {
        departure = min(max(newValue, Date()), maxDeparture)
        departureDebounceTask?.cancel()
        departureDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await recomputeForDepartureChange()
        }
    }

    func stopsChangedReplan() {
        guard origin != nil, destination != nil, !routes.isEmpty else { return }
        if isOnline {
            planRoute()
        } else {
            routes = routes.map { routeService.recomputeETAs(for: $0, departure: departure, stops: stops) }
            applyOfflineWeatherRematch()
            persistCurrentTrip()
        }
    }

    // MARK: - Persistence

    func reloadRecent() {
        recentTrips = TripStore.recentTrips
    }

    func openRecent(_ trip: Trip) {
        origin = trip.origin
        destination = trip.destination
        stops = trip.stops
        departure = max(trip.departure, Date())
        routes = trip.routes
        selectedRouteID = trip.selectedRouteID ?? trip.routes.first?.id
        arrivalBrief = trip.arrivalBrief ?? ""
        activeTripID = trip.id
        errorMessage = nil
        goNowError = nil

        if routes.isEmpty { return }

        // Remap ETAs for current departure using cached geometry.
        routes = routes.map { routeService.recomputeETAs(for: $0, departure: departure, stops: stops) }

        if isOnline {
            needsWeatherRefreshHint = false
            Task { await enrichAllRoutesWeather() }
        } else {
            applyOfflineWeatherRematch()
        }
    }

    func saveCurrentTrip() {
        persistCurrentTrip()
        reloadRecent()
    }

    func deleteRecent(_ trip: Trip) {
        TripStore.remove(trip)
        reloadRecent()
    }

    // MARK: - Go Now

    func startGoNow() {
        guard let route = selectedRoute, let destination else { return }
        goNowError = nil
        let trip = makeTripSnapshot()
        // Force departure to now for a live drive session.
        departure = Date()
        let liveRoute = routeService.recomputeETAs(for: route, departure: departure, stops: stops)
        if let index = routes.firstIndex(where: { $0.id == route.id }) {
            routes[index] = liveRoute
        }

        switch TripLiveActivityManager.shared.start(
            trip: trip,
            route: liveRoute,
            destinationName: destination.name
        ) {
        case .started:
            TripAheadAlertScheduler.shared.schedule(for: liveRoute, destinationName: destination.name)
            isTripLive = true
            persistCurrentTrip()
        case .disabled:
            isTripLive = false
            goNowError = "Turn on Live Activities for Breezy in Settings to use Go Now on the Lock Screen and Dynamic Island."
        case .failed(let message):
            isTripLive = false
            goNowError = "Couldn't start Live Activity: \(message)"
        }
    }

    func endGoNow() {
        TripLiveActivityManager.shared.end()
        TripAheadAlertScheduler.shared.cancel()
        isTripLive = false
        goNowError = nil
    }

    // MARK: - Private

    private func recomputeForDepartureChange() async {
        guard !routes.isEmpty else { return }
        routes = routes.map { routeService.recomputeETAs(for: $0, departure: departure, stops: stops) }

        if isOnline {
            needsWeatherRefreshHint = false
            await enrichAllRoutesWeather()
        } else {
            applyOfflineWeatherRematch()
            isLoadingWeather = false
        }
        persistCurrentTrip()
    }

    /// Remap each sample's weather to the nearest cached forecast hour for its new ETA.
    private func applyOfflineWeatherRematch() {
        var updated = routes
        var allCovered = true
        for index in updated.indices {
            let result = TripWeatherService.shared.rematchSamplesToNearestCachedHour(updated[index].samples)
            updated[index].samples = result.samples
            updated[index].riskScore = TripWeatherService.shared.riskScore(for: result.samples)
            if !result.fullyCovered { allCovered = false }
        }
        routes = updated
        needsWeatherRefreshHint = !allCovered
        if let route = selectedRoute {
            arrivalBrief = TripWeatherService.shared.arrivalBrief(
                for: route.samples,
                destinationName: destination?.name ?? "destination"
            )
        }
    }

    private func enrichAllRoutesWeather() async {
        weatherGeneration += 1
        let generation = weatherGeneration
        isLoadingWeather = true

        var updatedRoutes = routes
        for index in updatedRoutes.indices {
            let samples = updatedRoutes[index].samples
            let enriched = await TripWeatherService.shared.enrichSamples(samples) { progressive in
                Task { @MainActor in
                    guard generation == self.weatherGeneration else { return }
                    var copy = self.routes
                    guard index < copy.count else { return }
                    copy[index].samples = progressive
                    copy[index].riskScore = 0
                    self.routes = copy
                }
            }
            guard generation == weatherGeneration else { return }
            updatedRoutes[index].samples = enriched
            updatedRoutes[index].riskScore = TripWeatherService.shared.riskScore(for: enriched)
        }

        updatedRoutes.sort {
            if abs($0.riskScore - $1.riskScore) < 0.5 {
                return $0.expectedTravelTime < $1.expectedTravelTime
            }
            return $0.riskScore < $1.riskScore
        }

        if let selectedRouteID, updatedRoutes.contains(where: { $0.id == selectedRouteID }) {
            // keep
        } else {
            selectedRouteID = updatedRoutes.first?.id
        }

        routes = updatedRoutes
        if let route = selectedRoute {
            arrivalBrief = TripWeatherService.shared.arrivalBrief(
                for: route.samples,
                destinationName: destination?.name ?? "destination"
            )
        }
        isLoadingWeather = false
        needsWeatherRefreshHint = false
    }

    private func persistCurrentTrip() {
        guard let origin, let destination, !routes.isEmpty else { return }
        let trip = makeTripSnapshot()
        TripStore.save(trip)
        activeTripID = trip.id
        reloadRecent()
    }

    private func makeTripSnapshot() -> Trip {
        Trip(
            id: activeTripID ?? UUID(),
            origin: origin ?? TripEndpoint(name: "Start", latitude: 0, longitude: 0),
            destination: destination ?? TripEndpoint(name: "End", latitude: 0, longitude: 0),
            stops: stops,
            departure: departure,
            selectedRouteID: selectedRouteID,
            routes: routes,
            arrivalBrief: arrivalBrief
        )
    }
}
