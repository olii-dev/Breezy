//
//  TripStore.swift
//  Breezy
//
//  Persist recent On the Way plans + Go Now snapshot in the App Group.
//

import Foundation
import WidgetKit

struct TripStore {
    private static let tripsKey = "Breezy.OnTheWay.RecentTrips"
    private static let legacyTripsKey = "Breezy.TripMode.RecentTrips"
    private static let goNowKey = "Breezy.OnTheWay.GoNowSnapshot"
    private static let goNowRouteKey = "Breezy.OnTheWay.GoNowRoute"
    private static let summaryKey = "Breezy.OnTheWay.WidgetSummary"
    private static let maxCount = 12
    private static let appGroupID = "group.com.breezy.weather"

    private static let widgetKind = "OnTheWayWidget"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static var recentTrips: [Trip] {
        get {
            if let data = defaults.data(forKey: tripsKey),
               let decoded = try? JSONDecoder().decode([Trip].self, from: data) {
                return decoded
            }
            // One-time migrate from standard defaults.
            if let data = UserDefaults.standard.data(forKey: legacyTripsKey),
               let decoded = try? JSONDecoder().decode([Trip].self, from: data) {
                recentTrips = decoded
                UserDefaults.standard.removeObject(forKey: legacyTripsKey)
                return decoded
            }
            return []
        }
        set {
            if let encoded = try? JSONEncoder().encode(Array(newValue.prefix(maxCount))) {
                defaults.set(encoded, forKey: tripsKey)
            }
            refreshWidgetSummary(from: newValue.first)
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        }
    }

    static func save(_ trip: Trip) {
        var list = recentTrips
        list.removeAll { $0.id == trip.id }
        list.removeAll {
            $0.origin.id == trip.origin.id && $0.destination.id == trip.destination.id
        }
        list.insert(trip, at: 0)
        recentTrips = list
    }

    static func remove(_ trip: Trip) {
        recentTrips = recentTrips.filter { $0.id != trip.id }
    }

    static func clear() {
        recentTrips = []
    }

    // MARK: - Go Now snapshot (app-group truth for "on a trip")

    static var goNowSnapshot: TripGoNowSnapshot {
        get {
            guard let data = defaults.data(forKey: goNowKey),
                  let decoded = try? JSONDecoder().decode(TripGoNowSnapshot.self, from: data) else {
                return .inactive
            }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                defaults.set(encoded, forKey: goNowKey)
            }
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        }
    }

    static func clearGoNowSnapshot() {
        goNowSnapshot = .inactive
        goNowRoute = nil
        goNowStartedAt = nil
    }

    /// A snapshot only counts as an active trip while fresh: at most 3 hours
    /// old, with an hour's grace past the recorded ETA. Anything older is a
    /// crashed-or-forgotten trip, not a live one.
    static func isGoNowActive(now: Date = Date()) -> Bool {
        let snapshot = goNowSnapshot
        guard snapshot.isActive else { return false }
        let eta = goNowStartedAt.map { $0.addingTimeInterval(goNowRoute?.expectedTravelTime ?? 0) }
        let deadline = max(goNowStartedAt?.addingTimeInterval(3 * 60 * 60) ?? .distantPast,
                           eta?.addingTimeInterval(45 * 60) ?? .distantPast)
        return now < deadline
    }

    /// The full route captured at Go Now, so a relaunched app can restore the
    /// Live Activity, tracker and in-app driving state.
    static var goNowRoute: TripRouteOption? {
        get {
            guard let data = defaults.data(forKey: goNowRouteKey),
                  let decoded = try? JSONDecoder().decode(TripRouteOption.self, from: data) else {
                return nil
            }
            return decoded
        }
        set {
            if let newValue, let encoded = try? JSONEncoder().encode(newValue) {
                defaults.set(encoded, forKey: goNowRouteKey)
            } else {
                defaults.removeObject(forKey: goNowRouteKey)
            }
        }
    }

    static var goNowStartedAt: Date? {
        get { defaults.object(forKey: "\(goNowRouteKey).startedAt") as? Date }
        set {
            if let newValue {
                defaults.set(newValue, forKey: "\(goNowRouteKey).startedAt")
            } else {
                defaults.removeObject(forKey: "\(goNowRouteKey).startedAt")
            }
        }
    }

    static var widgetSummary: TripWidgetSummary? {
        get {
            guard let data = defaults.data(forKey: summaryKey),
                  let decoded = try? JSONDecoder().decode(TripWidgetSummary.self, from: data) else {
                return nil
            }
            return decoded
        }
        set {
            if let newValue, let encoded = try? JSONEncoder().encode(newValue) {
                defaults.set(encoded, forKey: summaryKey)
            } else {
                defaults.removeObject(forKey: summaryKey)
            }
        }
    }

    static func refreshWidgetSummary(from trip: Trip?) {
        guard let trip, let route = trip.selectedRoute ?? trip.routes.first else {
            widgetSummary = nil
            return
        }
        let arrival = route.samples.last
        let rough = route.samples.first {
            !$0.riskFlags.isEmpty || ($0.weather?.precipitationProbability ?? 0) >= 0.55
        }
        widgetSummary = TripWidgetSummary(
            originName: trip.origin.name,
            destinationName: trip.destination.name,
            departure: trip.departure,
            arrivalETA: arrival?.eta,
            arrivalCondition: arrival?.weather?.condition,
            arrivalTemperatureText: arrival?.weather?.formattedTemperature,
            nextRoughStretch: {
                guard let rough else { return nil }
                if let flag = rough.riskFlags.first {
                    return "\(flag.title) near \(rough.placeLabel)"
                }
                return rough.weather.map { "\($0.condition) near \(rough.placeLabel)" }
            }(),
            travelTimeText: route.travelTimeFormatted
        )
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}
