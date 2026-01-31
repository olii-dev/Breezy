//
//  WatchLocationSearchService.swift
//  Breezy Watch Watch App
//
//  Wraps MKLocalSearch to find cities.
//

import Foundation
import MapKit
import Combine

class WatchLocationSearchResults: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    @Published var isSearching = false
    
    private var completer: MKLocalSearchCompleter
    
    override init() {
        completer = MKLocalSearchCompleter()
        super.init()
        completer.delegate = self
        // Default resultTypes includes address, pointOfInterest, and query, which is better for "London" etc.
    }
    
    func search(query: String) {
        guard !query.isEmpty else {
            results = []
            return
        }
        isSearching = true
        completer.queryFragment = query
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // Filter mainly for localities/cities if possible or just show all addresses
        // Watch users mostly search for Cities.
        DispatchQueue.main.async {
            self.results = completer.results.filter { $0.title.count > 0 }
            self.isSearching = false
        }
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("Search error: \(error.localizedDescription)")
        isSearching = false
    }
}

class WatchLocationSearchService {
    static func getCoordinates(for completion: MKLocalSearchCompletion) async throws -> (lat: Double, long: Double, name: String) {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        
        let response = try await search.start()
        guard let item = response.mapItems.first else {
            throw NSError(domain: "Breezy", code: 404, userInfo: [NSLocalizedDescriptionKey: "Location not found"])
        }
        
        let coordinate = item.placemark.coordinate
        // Use the title from the completion or placemark
        let name = item.name ?? completion.title.components(separatedBy: ",").first ?? completion.title
        
        return (coordinate.latitude, coordinate.longitude, name)
    }
}
