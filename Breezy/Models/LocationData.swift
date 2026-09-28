//
//  LocationData.swift
//  Breezy
//
//  Location data model
//

import Foundation

struct LocationData: Identifiable, Codable, Equatable {
    var id: String { "\(city)-\(coordinateString)" }
    let city: String
    let latitude: Double
    let longitude: Double
    var timezoneIdentifier: String? = nil
    /// Region/country for display (e.g. "South Australia, Australia"); older
    /// saved locations decode as nil and fall back to coordinates.
    var region: String? = nil

    var displaySubtitle: String { region ?? coordinateString }
    
    var coordinateString: String {
        String(format: "%.4f,%.4f", latitude, longitude)
    }
}

