//
//  FavouritesStore.swift
//  Breezy
//
//  Favourite locations storage
//

import Foundation

struct FavouritesStore {
    private static let key = "Breezy.FavouritesV2"
    
    static var favourites: [LocationData] {
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
        var list = favourites
        list.removeAll { $0.city == location.city }
        list.insert(location, at: 0)
        favourites = Array(list.prefix(10))
    }
    
    static func remove(_ location: LocationData) {
        favourites = favourites.filter { $0.city != location.city }
    }
    
    static func clear() {
        favourites = []
    }
}

