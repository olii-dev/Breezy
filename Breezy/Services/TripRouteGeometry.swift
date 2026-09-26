//
//  TripRouteGeometry.swift
//  Breezy
//
//  Polyline projection for GPS-lite progress along a driving route.
//

import Foundation
import CoreLocation

enum TripRouteGeometry {
    struct Snap {
        /// Meters along the route from the start.
        var distanceAlong: Double
        /// Meters left to the end.
        var remaining: Double
        /// Progress 0...1.
        var progress: Double
        /// Distance from the user to the nearest point on the polyline.
        var crossTrackMeters: Double
        var coordinate: CLLocationCoordinate2D
    }

    /// Project `location` onto the route polyline (segment-level), not just nearest vertex.
    static func snap(location: CLLocation, onto route: TripRouteOption) -> Snap {
        let coords = route.coordinates.map(\.coordinate)
        let total = max(route.distanceMeters, 1)

        guard coords.count >= 2 else {
            let c = coords.first ?? location.coordinate
            return Snap(distanceAlong: 0, remaining: total, progress: 0, crossTrackMeters: 0, coordinate: c)
        }

        var best = Snap(
            distanceAlong: 0,
            remaining: total,
            progress: 0,
            crossTrackMeters: .greatestFiniteMagnitude,
            coordinate: coords[0]
        )
        var traveled: Double = 0

        for i in 0..<(coords.count - 1) {
            let a = coords[i]
            let b = coords[i + 1]
            let segmentLength = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            guard segmentLength > 0.5 else { continue }

            let projected = project(point: location.coordinate, ontoSegmentFrom: a, to: b)
            let cross = CLLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                .distance(from: CLLocation(latitude: projected.coordinate.latitude, longitude: projected.coordinate.longitude))

            if cross < best.crossTrackMeters {
                let along = traveled + projected.t * segmentLength
                let clampedAlong = min(max(along, 0), total)
                best = Snap(
                    distanceAlong: clampedAlong,
                    remaining: max(0, total - clampedAlong),
                    progress: min(1, max(0, clampedAlong / total)),
                    crossTrackMeters: cross,
                    coordinate: projected.coordinate
                )
            }
            traveled += segmentLength
        }

        return best
    }

    /// Unitless projection of a point onto segment AB. `t` is clamped to 0...1.
    private static func project(
        point: CLLocationCoordinate2D,
        ontoSegmentFrom a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D
    ) -> (coordinate: CLLocationCoordinate2D, t: Double) {
        // Local equirectangular meters relative to A.
        let latRad = a.latitude * .pi / 180
        let metersPerDegLat = 111_320.0
        let metersPerDegLon = 111_320.0 * cos(latRad)

        let ax = 0.0, ay = 0.0
        let bx = (b.longitude - a.longitude) * metersPerDegLon
        let by = (b.latitude - a.latitude) * metersPerDegLat
        let px = (point.longitude - a.longitude) * metersPerDegLon
        let py = (point.latitude - a.latitude) * metersPerDegLat

        let ab2 = bx * bx + by * by
        guard ab2 > 1e-6 else {
            return (a, 0)
        }

        var t = (px * bx + py * by) / ab2
        t = min(1, max(0, t))
        let cx = ax + t * bx
        let cy = ay + t * by
        let coordinate = CLLocationCoordinate2D(
            latitude: a.latitude + cy / metersPerDegLat,
            longitude: a.longitude + cx / metersPerDegLon
        )
        return (coordinate, t)
    }
}
