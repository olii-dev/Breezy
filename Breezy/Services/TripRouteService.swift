//
//  TripRouteService.swift
//  Breezy
//
//  MapKit directions, polyline sampling, and ETA chaining with stops.
//

import Foundation
import MapKit
import CoreLocation

enum TripRouteError: LocalizedError {
    case missingEndpoints
    case noRoutes
    case directionsFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingEndpoints: return "Choose both a start and a destination."
        case .noRoutes: return "No driving routes found for this trip."
        case .directionsFailed(let message): return message
        }
    }
}

final class TripRouteService {
    static let shared = TripRouteService()

    /// Cap sample count to keep weather API load bounded.
    static let maxSampleCount = 32
    static let minSampleCount = 12

    private init() {}

    // MARK: - Public API

    /// Builds one or more driving route options for origin → stops → destination.
    /// Alternates are requested on the first (or only) leg when there are no mid stops.
    func fetchRouteOptions(
        origin: TripEndpoint,
        destination: TripEndpoint,
        stops: [TripStop] = [],
        departure: Date,
        includeAlternates: Bool = true
    ) async throws -> [TripRouteOption] {
        let waypoints = [origin] + stops.map(\.endpoint) + [destination]
        guard waypoints.count >= 2 else { throw TripRouteError.missingEndpoints }

        if stops.isEmpty {
            return try await fetchSingleLegOptions(
                origin: origin,
                destination: destination,
                departure: departure,
                includeAlternates: includeAlternates
            )
        }

        // Multi-stop: stitch sequential preferred routes; dwell shifts later ETAs.
        let primary = try await fetchStitchedRoute(
            waypoints: waypoints,
            stopDwellsMinutes: stops.map(\.dwellMinutes),
            departure: departure,
            name: "Best route"
        )
        return [primary]
    }

    // MARK: - Single-leg with alternates

    private func fetchSingleLegOptions(
        origin: TripEndpoint,
        destination: TripEndpoint,
        departure: Date,
        includeAlternates: Bool
    ) async throws -> [TripRouteOption] {
        let response = try await calculateDirections(
            from: origin,
            to: destination,
            departure: departure,
            includeAlternates: includeAlternates
        )

        guard !response.routes.isEmpty else { throw TripRouteError.noRoutes }

        return response.routes.enumerated().map { index, route in
            makeOption(
                from: route,
                name: routeName(route, index: index, total: response.routes.count),
                departure: departure,
                dwellOffsets: []
            )
        }
    }

    // MARK: - Multi-stop stitch

    private func fetchStitchedRoute(
        waypoints: [TripEndpoint],
        stopDwellsMinutes: [Int],
        departure: Date,
        name: String
    ) async throws -> TripRouteOption {
        do {
            return try await stitchWaypoints(
                waypoints: waypoints,
                stopDwellsMinutes: stopDwellsMinutes,
                departure: departure,
                name: name
            )
        } catch {
            // MapKit often refuses multi-leg / far-future requests. Fall back to a direct
            // origin→destination drive and apply stop dwells at nearest points on that path.
            guard waypoints.count >= 2 else { throw error }
            let origin = waypoints[0]
            let destination = waypoints[waypoints.count - 1]
            let response = try await calculateDirections(
                from: origin,
                to: destination,
                departure: departure,
                includeAlternates: false
            )
            guard let route = response.routes.first else { throw TripRouteError.noRoutes }
            let coords = coordinates(from: route.polyline)
            let cumulative = cumulativeDistances(along: coords)
            let pathLength = cumulative.last ?? route.distance

            let stopEndpoints = Array(waypoints.dropFirst().dropLast())
            var dwellAtDistances: [(distance: Double, dwellSeconds: TimeInterval)] = []
            for (index, stop) in stopEndpoints.enumerated() {
                let distance = nearestDistance(on: coords, cumulative: cumulative, to: stop.coordinate)
                let dwellMinutes = index < stopDwellsMinutes.count ? stopDwellsMinutes[index] : 15
                dwellAtDistances.append((distance: distance, dwellSeconds: TimeInterval(dwellMinutes * 60)))
            }
            dwellAtDistances.sort { $0.distance < $1.distance }

            let dwellTotal = dwellAtDistances.reduce(0.0) { $0 + $1.dwellSeconds }
            let samples = sampleCoordinates(
                coords,
                totalDistanceMeters: pathLength,
                departure: departure,
                pureDrivingTime: route.expectedTravelTime,
                dwellAtDistances: dwellAtDistances
            )
            return TripRouteOption(
                name: name,
                distanceMeters: route.distance,
                expectedTravelTime: route.expectedTravelTime + dwellTotal,
                coordinates: coords.map(TripRouteCoordinate.init),
                samples: samples
            )
        }
    }

    private func stitchWaypoints(
        waypoints: [TripEndpoint],
        stopDwellsMinutes: [Int],
        departure: Date,
        name: String
    ) async throws -> TripRouteOption {
        var allCoordinates: [CLLocationCoordinate2D] = []
        var totalDistance: CLLocationDistance = 0
        var totalTravel: TimeInterval = 0
        var dwellAtDistances: [(distance: Double, dwellSeconds: TimeInterval)] = []

        for i in 0..<(waypoints.count - 1) {
            let response = try await calculateDirections(
                from: waypoints[i],
                to: waypoints[i + 1],
                departure: departure.addingTimeInterval(totalTravel),
                includeAlternates: false
            )
            guard let route = response.routes.first else { throw TripRouteError.noRoutes }

            let coords = coordinates(from: route.polyline)
            if allCoordinates.isEmpty {
                allCoordinates.append(contentsOf: coords)
            } else if coords.count > 1 {
                allCoordinates.append(contentsOf: coords.dropFirst())
            }

            totalDistance += route.distance
            totalTravel += route.expectedTravelTime

            if i < stopDwellsMinutes.count {
                let dwell = TimeInterval(stopDwellsMinutes[i] * 60)
                dwellAtDistances.append((distance: totalDistance, dwellSeconds: dwell))
                totalTravel += dwell
            }
        }

        let samples = sampleCoordinates(
            allCoordinates,
            totalDistanceMeters: totalDistance,
            departure: departure,
            pureDrivingTime: totalTravel - dwellAtDistances.reduce(0) { $0 + $1.dwellSeconds },
            dwellAtDistances: dwellAtDistances
        )

        return TripRouteOption(
            name: name,
            distanceMeters: totalDistance,
            expectedTravelTime: totalTravel,
            coordinates: allCoordinates.map(TripRouteCoordinate.init),
            samples: samples
        )
    }

    /// MapKit rejects many far-future `departureDate` values with "Directions Not Available".
    /// Only attach a departure hint when it's soon; geometry/travel time still work without it.
    private func calculateDirections(
        from origin: TripEndpoint,
        to destination: TripEndpoint,
        departure: Date,
        includeAlternates: Bool
    ) async throws -> MKDirections.Response {
        let source = await resolvedMapItem(for: origin)
        let dest = await resolvedMapItem(for: destination)

        func attempt(withDepartureDate: Bool) async throws -> MKDirections.Response {
            let request = MKDirections.Request()
            request.source = source
            request.destination = dest
            request.transportType = .automobile
            request.requestsAlternateRoutes = includeAlternates
            if withDepartureDate, departure.timeIntervalSinceNow < 24 * 3600 {
                request.departureDate = max(departure, Date())
            }
            return try await MKDirections(request: request).calculate()
        }

        do {
            return try await attempt(withDepartureDate: true)
        } catch {
            do {
                return try await attempt(withDepartureDate: false)
            } catch {
                throw TripRouteError.directionsFailed(error.localizedDescription)
            }
        }
    }

    // MARK: - Option builders

    private func makeOption(
        from route: MKRoute,
        name: String,
        departure: Date,
        dwellOffsets: [(distance: Double, dwellSeconds: TimeInterval)]
    ) -> TripRouteOption {
        let coords = coordinates(from: route.polyline)
        let samples = sampleCoordinates(
            coords,
            totalDistanceMeters: route.distance,
            departure: departure,
            pureDrivingTime: route.expectedTravelTime,
            dwellAtDistances: dwellOffsets
        )
        return TripRouteOption(
            name: name,
            distanceMeters: route.distance,
            expectedTravelTime: route.expectedTravelTime,
            coordinates: coords.map(TripRouteCoordinate.init),
            samples: samples
        )
    }

    /// Recompute sample ETAs when departure or dwells change without re-fetching directions.
    func recomputeETAs(
        for option: TripRouteOption,
        departure: Date,
        stops: [TripStop]
    ) -> TripRouteOption {
        // Approximate dwell application: distribute stop dwells evenly by index along the route
        // when we don't have exact stop distances (single-leg path). Multi-stop options already
        // baked dwell into expectedTravelTime; for slider scrub we scale by distance fraction.
        var updated = option
        let drivingTime: TimeInterval
        let dwellTotal = TimeInterval(stops.reduce(0) { $0 + $1.dwellMinutes } * 60)

        if stops.isEmpty {
            drivingTime = option.expectedTravelTime
        } else {
            // expectedTravelTime includes dwell for stitched routes
            drivingTime = max(60, option.expectedTravelTime - dwellTotal)
        }

        let totalDistance = max(option.distanceMeters, 1)
        let dwellMarks: [(distance: Double, dwellSeconds: TimeInterval)] = stops.enumerated().map { index, stop in
            let fraction = Double(index + 1) / Double(stops.count + 1)
            return (distance: totalDistance * fraction, dwellSeconds: TimeInterval(stop.dwellMinutes * 60))
        }

        updated.samples = option.samples.map { sample in
            var copy = sample
            copy.eta = eta(
                at: sample.distanceFromStartMeters,
                totalDistance: totalDistance,
                departure: departure,
                pureDrivingTime: drivingTime,
                dwellAtDistances: dwellMarks
            )
            return copy
        }
        updated.expectedTravelTime = drivingTime + dwellTotal
        return updated
    }

    // MARK: - Sampling

    func sampleCoordinates(
        _ coordinates: [CLLocationCoordinate2D],
        totalDistanceMeters: CLLocationDistance,
        departure: Date,
        pureDrivingTime: TimeInterval,
        dwellAtDistances: [(distance: Double, dwellSeconds: TimeInterval)]
    ) -> [TripSamplePoint] {
        guard coordinates.count >= 2, totalDistanceMeters > 0 else { return [] }

        let cumulative = cumulativeDistances(along: coordinates)
        let pathLength = cumulative.last ?? totalDistanceMeters
        let count = sampleCount(forDistanceMeters: max(pathLength, totalDistanceMeters))
        var samples: [TripSamplePoint] = []

        for i in 0..<count {
            let fraction = count == 1 ? 0.0 : Double(i) / Double(count - 1)
            let targetDistance = pathLength * fraction
            let coordinate = interpolate(along: coordinates, cumulative: cumulative, targetDistance: targetDistance)
            let etaDate = eta(
                at: targetDistance,
                totalDistance: pathLength,
                departure: departure,
                pureDrivingTime: pureDrivingTime,
                dwellAtDistances: dwellAtDistances
            )
            let label: String
            if i == 0 {
                label = "Departure"
            } else if i == count - 1 {
                label = "Arrival"
            } else {
                label = String(format: "%.0f km", targetDistance / 1000.0)
            }
            samples.append(
                TripSamplePoint(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    distanceFromStartMeters: targetDistance,
                    eta: etaDate,
                    placeLabel: label
                )
            )
        }
        return samples
    }

    private func sampleCount(forDistanceMeters distance: CLLocationDistance) -> Int {
        // ~1 sample per 15 km, clamped.
        let adaptive = Int((distance / 15_000).rounded()) + 8
        return min(Self.maxSampleCount, max(Self.minSampleCount, adaptive))
    }

    private func eta(
        at distance: Double,
        totalDistance: Double,
        departure: Date,
        pureDrivingTime: TimeInterval,
        dwellAtDistances: [(distance: Double, dwellSeconds: TimeInterval)]
    ) -> Date {
        let fraction = min(1, max(0, distance / max(totalDistance, 1)))
        var elapsed = pureDrivingTime * fraction
        for mark in dwellAtDistances where mark.distance <= distance + 1 {
            elapsed += mark.dwellSeconds
        }
        return departure.addingTimeInterval(elapsed)
    }

    // MARK: - Geometry helpers

    private func coordinates(from polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        var coords = Array(repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        return coords.filter { CLLocationCoordinate2DIsValid($0) }
    }

    private func cumulativeDistances(along coordinates: [CLLocationCoordinate2D]) -> [CLLocationDistance] {
        var result: [CLLocationDistance] = [0]
        guard coordinates.count > 1 else { return result }
        var total: CLLocationDistance = 0
        for i in 1..<coordinates.count {
            let a = CLLocation(latitude: coordinates[i - 1].latitude, longitude: coordinates[i - 1].longitude)
            let b = CLLocation(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude)
            total += a.distance(from: b)
            result.append(total)
        }
        return result
    }

    private func interpolate(
        along coordinates: [CLLocationCoordinate2D],
        cumulative: [CLLocationDistance],
        targetDistance: CLLocationDistance
    ) -> CLLocationCoordinate2D {
        guard let last = coordinates.last else {
            return coordinates.first ?? CLLocationCoordinate2D()
        }
        if targetDistance <= 0 { return coordinates[0] }
        if targetDistance >= (cumulative.last ?? 0) { return last }

        var index = 1
        while index < cumulative.count && cumulative[index] < targetDistance {
            index += 1
        }
        let prev = index - 1
        let segmentStart = cumulative[prev]
        let segmentEnd = cumulative[index]
        let span = max(segmentEnd - segmentStart, 1)
        let t = (targetDistance - segmentStart) / span
        let a = coordinates[prev]
        let b = coordinates[index]
        return CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }

    private func resolvedMapItem(for endpoint: TripEndpoint) async -> MKMapItem {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = endpoint.name
        request.resultTypes = [.address, .pointOfInterest]
        request.region = MKCoordinateRegion(
            center: endpoint.coordinate,
            latitudinalMeters: 8_000,
            longitudinalMeters: 8_000
        )
        if let response = try? await MKLocalSearch(request: request).start() {
            let origin = CLLocation(latitude: endpoint.latitude, longitude: endpoint.longitude)
            if let best = response.mapItems.min(by: { a, b in
                let aLoc = a.placemark.location ?? CLLocation(latitude: a.placemark.coordinate.latitude, longitude: a.placemark.coordinate.longitude)
                let bLoc = b.placemark.location ?? CLLocation(latitude: b.placemark.coordinate.latitude, longitude: b.placemark.coordinate.longitude)
                return aLoc.distance(from: origin) < bLoc.distance(from: origin)
            }) {
                return best
            }
        }

        let placemark = MKPlacemark(coordinate: endpoint.coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = endpoint.name
        return item
    }

    private func nearestDistance(
        on coordinates: [CLLocationCoordinate2D],
        cumulative: [CLLocationDistance],
        to coordinate: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        guard !coordinates.isEmpty, coordinates.count == cumulative.count else { return 0 }
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, point) in coordinates.enumerated() {
            let distance = CLLocation(latitude: point.latitude, longitude: point.longitude).distance(from: target)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return cumulative[bestIndex]
    }

    private func routeName(_ route: MKRoute, index: Int, total: Int) -> String {
        if !route.name.isEmpty { return route.name }
        if total == 1 { return "Best route" }
        return index == 0 ? "Best route" : "Alternate \(index)"
    }
}
