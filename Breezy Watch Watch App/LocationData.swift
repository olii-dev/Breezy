//
//  LocationData.swift
//  Breezy Watch Watch App
//
//  Location data model for Watch app
//

import Foundation

struct LocationData: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    let city: String
    let latitude: Double
    let longitude: Double
    
    var coordinateString: String {
        String(format: "%.4f,%.4f", latitude, longitude)
    }
}




