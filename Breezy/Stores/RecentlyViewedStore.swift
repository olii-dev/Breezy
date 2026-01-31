//
//  RecentlyViewedStore.swift
//  Breezy
//
//  Recently viewed locations storage
//

import Foundation

struct RecentlyViewedStore {
    private static let key = "Breezy.RecentlyViewedV2"
    
    static var recentLocations: [LocationData] {
        get {
            guard let data = CloudStorage.shared.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([LocationData].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            if let encoded = try? JSONEncoder().encode(newValue) {
                CloudStorage.shared.set(encoded, forKey: key)
            }
        }
    }
    
    static func add(_ location: LocationData) {
        var list = recentLocations
        list.removeAll { $0.city == location.city }
        list.insert(location, at: 0)
        recentLocations = Array(list.prefix(15))
    }
    
    static func remove(_ location: LocationData) {
        recentLocations = recentLocations.filter { $0.city != location.city }
    }
    
    static func clear() {
        recentLocations = []
    }
}

