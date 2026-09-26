//
//  TripModels.swift
//  Breezy
//
//  Trip Mode models — route samples, stops, weather snapshots, risk.
//

import Foundation
import CoreLocation

struct TripEndpoint: Codable, Equatable, Identifiable, Hashable {
    var id: String { "\(name)-\(String(format: "%.4f,%.4f", latitude, longitude))" }
    var name: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var locationData: LocationData {
        LocationData(city: name, latitude: latitude, longitude: longitude)
    }

    init(name: String, latitude: Double, longitude: Double) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }

    init(location: LocationData) {
        self.name = location.city
        self.latitude = location.latitude
        self.longitude = location.longitude
    }
}

struct TripStop: Codable, Equatable, Identifiable, Hashable {
    var id: UUID
    var endpoint: TripEndpoint
    /// Minutes spent at this stop before continuing.
    var dwellMinutes: Int

    init(id: UUID = UUID(), endpoint: TripEndpoint, dwellMinutes: Int = 15) {
        self.id = id
        self.endpoint = endpoint
        self.dwellMinutes = max(0, dwellMinutes)
    }
}

struct TripWeatherSnapshot: Codable, Equatable, Hashable {
    var temperatureCelsius: Double
    var condition: String
    var weatherCode: Int
    var precipitationProbability: Double // 0...1
    var precipitationMillimeters: Double
    var windSpeedMetersPerSecond: Double
    var windGustMetersPerSecond: Double?
    var visibilityMeters: Double?

    var displayTemperature: (value: Double, symbol: String) {
        let unit = TemperatureUnit(rawValue: UserDefaults.standard.string(forKey: "Breezy.temperatureUnit") ?? "") ?? .celsius
        if unit == .fahrenheit {
            return (temperatureCelsius * 9.0 / 5.0 + 32.0, "F")
        }
        return (temperatureCelsius, "C")
    }

    var formattedTemperature: String {
        let display = displayTemperature
        return "\(Int(display.value.rounded()))°\(display.symbol)"
    }

    var formattedPrecipChance: String {
        "\(Int((precipitationProbability * 100).rounded()))%"
    }

    var formattedWind: String {
        let unit = WindSpeedUnit(rawValue: UserDefaults.standard.string(forKey: "Breezy.windSpeedUnit") ?? "") ?? .metersPerSecond
        let converted = unit.convert(windSpeedMetersPerSecond)
        return String(format: "%.0f %@", converted, unit.symbol)
    }
}

enum TripRiskFlag: String, Codable, Equatable, Hashable, CaseIterable {
    case heavyRain
    case strongWind
    case lowVisibility
    case snow
    case storms

    var title: String {
        switch self {
        case .heavyRain: return "Heavy rain"
        case .strongWind: return "Strong wind"
        case .lowVisibility: return "Low visibility"
        case .snow: return "Snow"
        case .storms: return "Storms"
        }
    }

    var systemImage: String {
        switch self {
        case .heavyRain: return "cloud.heavyrain.fill"
        case .strongWind: return "wind"
        case .lowVisibility: return "eye.slash.fill"
        case .snow: return "snowflake"
        case .storms: return "cloud.bolt.rain.fill"
        }
    }
}

struct TripSamplePoint: Codable, Equatable, Identifiable, Hashable {
    var id: UUID
    var latitude: Double
    var longitude: Double
    /// Distance from trip start along the driving path, meters.
    var distanceFromStartMeters: Double
    var eta: Date
    var placeLabel: String
    var weather: TripWeatherSnapshot?
    var riskFlags: [TripRiskFlag]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        distanceFromStartMeters: Double,
        eta: Date,
        placeLabel: String = "",
        weather: TripWeatherSnapshot? = nil,
        riskFlags: [TripRiskFlag] = []
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.distanceFromStartMeters = distanceFromStartMeters
        self.eta = eta
        self.placeLabel = placeLabel
        self.weather = weather
        self.riskFlags = riskFlags
    }
}

struct TripRouteCoordinate: Codable, Equatable, Hashable {
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }
}

struct TripRouteOption: Codable, Equatable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var distanceMeters: Double
    var expectedTravelTime: TimeInterval
    /// Polyline coordinates for map rendering.
    var coordinates: [TripRouteCoordinate]
    /// Sample points before weather fill-in (ETAs set; weather optional).
    var samples: [TripSamplePoint]
    /// Cumulative weather risk — lower is better.
    var riskScore: Double

    var distanceKilometers: Double { distanceMeters / 1000.0 }
    var travelTimeFormatted: String {
        let minutes = Int((expectedTravelTime / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rem = minutes % 60
        return rem == 0 ? "\(hours) hr" : "\(hours) hr \(rem) min"
    }

    init(
        id: UUID = UUID(),
        name: String,
        distanceMeters: Double,
        expectedTravelTime: TimeInterval,
        coordinates: [TripRouteCoordinate],
        samples: [TripSamplePoint],
        riskScore: Double = 0
    ) {
        self.id = id
        self.name = name
        self.distanceMeters = distanceMeters
        self.expectedTravelTime = expectedTravelTime
        self.coordinates = coordinates
        self.samples = samples
        self.riskScore = riskScore
    }
}

struct Trip: Codable, Equatable, Identifiable, Hashable {
    var id: UUID
    var origin: TripEndpoint
    var destination: TripEndpoint
    var stops: [TripStop]
    var departure: Date
    var selectedRouteID: UUID?
    var routes: [TripRouteOption]
    var createdAt: Date
    var arrivalBrief: String?

    init(
        id: UUID = UUID(),
        origin: TripEndpoint,
        destination: TripEndpoint,
        stops: [TripStop] = [],
        departure: Date = Date(),
        selectedRouteID: UUID? = nil,
        routes: [TripRouteOption] = [],
        createdAt: Date = Date(),
        arrivalBrief: String? = nil
    ) {
        self.id = id
        self.origin = origin
        self.destination = destination
        self.stops = stops
        self.departure = departure
        self.selectedRouteID = selectedRouteID
        self.routes = routes
        self.createdAt = createdAt
        self.arrivalBrief = arrivalBrief
    }

    var selectedRoute: TripRouteOption? {
        if let selectedRouteID {
            return routes.first { $0.id == selectedRouteID } ?? routes.first
        }
        return routes.first
    }

    var title: String {
        "\(origin.name) → \(destination.name)"
    }
}
