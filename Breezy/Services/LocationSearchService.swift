//
//  LocationSearchService.swift
//  Breezy
//
//  Provides autocompletion for location search using MapKit.
//

import Foundation
import MapKit
import Combine

class LocationSearchService: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var searchQuery = ""
    @Published var completions: [MKLocalSearchCompletion] = []
    @Published var status: LocationSearchStatus = .idle
    
    enum LocationSearchStatus {
        case idle
        case searching
        case noResults
        case error(String)
    }
    
    private var cancellables = Set<AnyCancellable>()
    private let completer = MKLocalSearchCompleter()
    
    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                if query.isEmpty {
                    self?.completions = []
                    self?.status = .idle
                } else {
                    self?.status = .searching
                    self?.completer.queryFragment = query
                }
            }
            .store(in: &cancellables)
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // Filter for cities/localities to avoid noise if desired, 
        // but .address generally covers what we want.
        // We can limit to valid results.
        self.completions = completer.results
        self.status = completer.results.isEmpty ? .noResults : .idle
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        self.status = .error(error.localizedDescription)
    }
    
    func getCoordinates(for completion: MKLocalSearchCompletion) async throws -> LocationData {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        
        let response = try await search.start()
        
        guard let item = response.mapItems.first,
              let location = item.placemark.location else {
            throw NSError(domain: "LocationSearch", code: 1, userInfo: [NSLocalizedDescriptionKey: "Location details not found"])
        }
        
        // Use locality (city) or name if locality is missing
        let city = item.placemark.locality ?? item.name ?? completion.title.components(separatedBy: ",").first ?? completion.title
        
        return LocationData(
            city: city,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
    }
}
