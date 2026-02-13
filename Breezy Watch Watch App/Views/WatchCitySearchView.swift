//
//  WatchCitySearchView.swift
//  Breezy Watch Watch App
//
//  Search for cities to add to the watch app.
//

import SwiftUI
import MapKit
// import WatchKit

struct WatchCitySearchView: View {
    @EnvironmentObject var viewModel: WatchWeatherViewModel
    @Environment(\.dismiss) var dismiss
    @StateObject private var searchResults = WatchLocationSearchResults()
    @State private var query = ""
    @State private var isGettingLocation = false
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        let theme = viewModel.currentTheme(isSystemDark: colorScheme == .dark)
        
        ZStack {
            // Background
            LinearGradient(
                gradient: Gradient(colors: [theme.topColor, theme.bottomColor]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Explicit Search Field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(theme.textColor.opacity(0.6))
                    TextField("Search City", text: $query)
                        .submitLabel(.search)
                        .foregroundColor(theme.textColor)
                    
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(theme.textColor.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .background(Material.regular)
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 8)
                
                if isGettingLocation {
                    VStack {
                        ProgressView()
                            .tint(theme.textColor)
                        Text("Adding...")
                            .font(.caption)
                            .foregroundColor(theme.textColor.opacity(0.8))
                    }
                    .frame(maxHeight: .infinity)
                } else if query.isEmpty {
                    if !viewModel.recentSearches.isEmpty {
                         List {
                             Section(header: Text("Recent").foregroundColor(theme.textColor.opacity(0.8))) {
                                 ForEach(viewModel.recentSearches) { recent in
                                     Button {
                                         // Just adding it again (selects it)
                                         viewModel.addLocation(name: recent.name, latitude: recent.latitude, longitude: recent.longitude)
                                         dismiss()
                                     } label: {
                                         HStack {
                                             Image(systemName: "clock")
                                                 .font(.caption2)
                                                 .foregroundColor(theme.textColor.opacity(0.6))
                                             Text(recent.name)
                                                 .font(.headline)
                                                 .foregroundColor(theme.textColor)
                                         }
                                         .padding(.vertical, 4)
                                     }
                                     .listRowBackground(Color.white.opacity(0.1))
                                 }
                                 .onDelete { indexSet in
                                     viewModel.deleteFromRecents(at: indexSet)
                                 }
                             }
                         }
                         .listStyle(.plain)
                         .scrollContentBackground(.hidden)
                    } else {
                        // Empty State
                        VStack(spacing: 8) {
    //                        Image(systemName: "magnifyingglass")
    //                            .font(.title2)
    //                            .foregroundStyle(theme.textColor.opacity(0.4))
                            Text("Dictate or Scribble")
                                .font(.caption2)
                                .foregroundStyle(theme.textColor.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                } else if searchResults.isSearching {
                    VStack {
                        ProgressView()
                            .tint(theme.textColor)
                    }
                    .frame(maxHeight: .infinity)
                } else if searchResults.results.isEmpty {
                    Text("No results found")
                        .foregroundStyle(theme.textColor.opacity(0.6))
                        .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(searchResults.results, id: \.self) { result in
                            Button {
                                addLocation(for: result)
                            } label: {
                                HStack {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(theme.textColor.opacity(0.5))
                                        
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.title)
                                            .font(.headline)
                                            .foregroundColor(theme.textColor)
                                        Text(result.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(theme.textColor.opacity(0.7))
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(Color.white.opacity(0.1))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle("Add City")
        .onChange(of: query) { _, newValue in
            searchResults.search(query: newValue)
        }
    }
    
    private func addLocation(for completion: MKLocalSearchCompletion) {
        isGettingLocation = true
        Task {
            do {
                let (lat, long, name) = try await WatchLocationSearchService.getCoordinates(for: completion)
                
                await MainActor.run {
                    WKInterfaceDevice.current().play(.success)
                    viewModel.addLocation(name: name, latitude: lat, longitude: long)
                    isGettingLocation = false
                    dismiss() // Dismiss Search
                }
            } catch {
                print("Error getting coords: \(error)")
                await MainActor.run {
                    WKInterfaceDevice.current().play(.failure)
                }
                isGettingLocation = false
            }
        }
    }

}
