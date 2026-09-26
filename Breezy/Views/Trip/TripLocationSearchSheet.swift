//
//  TripLocationSearchSheet.swift
//  Breezy
//
//  Lightweight place picker for Trip Mode endpoints / stops.
//

import SwiftUI
import MapKit

struct TripLocationSearchSheet: View {
    let title: String
    @ObservedObject var weatherViewModel: WeatherViewModel
    @ObservedObject var locationHelper: LocationHelper
    var showCurrentLocation: Bool = true
    let onPick: (LocationData) -> Void

    @StateObject private var searchService = LocationSearchService()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var isResolving = false

    private var theme: WeatherTheme {
        weatherViewModel.currentTheme(colorScheme: colorScheme)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground(colors: [theme.topColor, theme.bottomColor])
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(theme.textColor.opacity(0.5))
                        TextField("Search places", text: $searchService.searchQuery)
                            .foregroundStyle(theme.textColor)
                            .autocorrectionDisabled()
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                            .fill(.ultraThinMaterial.opacity(weatherViewModel.glassOpacity))
                    )
                    .padding(DesignSystem.spacingM)

                    List {
                        if showCurrentLocation {
                            Button {
                                Task {
                                    if let existing = locationHelper.userLocation {
                                        await MainActor.run {
                                            onPick(existing)
                                            dismiss()
                                        }
                                        return
                                    }
                                    do {
                                        let location = try await locationHelper.requestLocationAndGetData()
                                        let named = LocationData(
                                            city: weatherViewModel.weather?.location.city ?? location.city,
                                            latitude: location.latitude,
                                            longitude: location.longitude
                                        )
                                        await MainActor.run {
                                            onPick(named)
                                            dismiss()
                                        }
                                    } catch {
                                        // Keep sheet open; LocationHelper surfaces errors.
                                    }
                                }
                            } label: {
                                Label("Use current location", systemImage: "location.fill")
                                    .foregroundStyle(theme.textColor)
                            }
                            .listRowBackground(Color.clear)
                        }

                        ForEach(Array(searchService.completions.enumerated()), id: \.offset) { _, completion in
                            Button {
                                resolve(completion)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(completion.title)
                                        .foregroundStyle(theme.textColor)
                                    if !completion.subtitle.isEmpty {
                                        Text(completion.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(theme.textColor.opacity(0.6))
                                    }
                                }
                            }
                            .listRowBackground(Color.clear)
                            .disabled(isResolving)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(theme.textColor.opacity(0.7))
                    }
                }
            }
        }
    }

    private func resolve(_ completion: MKLocalSearchCompletion) {
        isResolving = true
        Task {
            defer { isResolving = false }
            do {
                let location = try await searchService.getCoordinates(for: completion)
                await MainActor.run {
                    onPick(location)
                    dismiss()
                }
            } catch {
                // Keep sheet open on failure.
            }
        }
    }
}
