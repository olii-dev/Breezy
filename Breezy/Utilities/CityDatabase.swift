//
//  CityDatabase.swift
//  Breezy
//
//  City search autocomplete database
//

import Foundation

struct CityDatabase {
    static func suggestions(for query: String) -> [String] {
        guard !query.isEmpty else { return [] }
        let lowercased = query.lowercased()
        
        // Load from JSON if available
        if let cities = loadCitiesFromJSON() {
            return cities.filter { $0.lowercased().hasPrefix(lowercased) }.prefix(8).map { $0 }
        }
        
        // Fallback to hardcoded cities
        return fallbackCities.filter { $0.lowercased().hasPrefix(lowercased) }.prefix(8).map { $0 }
    }
    
    private static func loadCitiesFromJSON() -> [String]? {
        guard let url = Bundle.main.url(forResource: "cities", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cities = json["cities"] as? [String] else {
            return nil
        }
        return cities
    }
    
    private static let fallbackCities = [
        "Adelaide", "Sydney", "Melbourne", "Brisbane", "Perth", "Hobart", "Darwin", "Canberra",
        "London", "Paris", "New York", "Tokyo", "Singapore", "Hong Kong", "Dubai", "Los Angeles",
        "San Francisco", "Seattle", "Chicago", "Boston", "Miami", "Toronto", "Vancouver", "Montreal"
    ]
}

