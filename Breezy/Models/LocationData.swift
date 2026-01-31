//
//  LocationData.swift
//  Breezy
//
//  Location data model
//

import Foundation

struct LocationData: Identifiable, Codable, Equatable {
    var id: UUID { UUID() }
    let city: String
    let latitude: Double
    let longitude: Double
    var timezoneIdentifier: String? = nil
    
    var coordinateString: String {
        String(format: "%.4f,%.4f", latitude, longitude)
    }
}

