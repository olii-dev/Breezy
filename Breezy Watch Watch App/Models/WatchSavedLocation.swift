//
//  WatchSavedLocation.swift
//  Breezy Watch Watch App
//
//  Model for persisted locations on Watch.
//

import Foundation

struct WatchSavedLocation: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String // e.g. "Paris"
    let latitude: Double
    let longitude: Double
    
    // Add subtitle or country if needed later
    // let country: String? 
    
    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}
