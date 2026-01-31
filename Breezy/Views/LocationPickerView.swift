
import SwiftUI
import MapKit

struct LocationPickerView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @ObservedObject var locationHelper: LocationHelper
    @Binding var isButtonBusy: Bool
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var searchService = LocationSearchService()
    @FocusState private var customCityFocused: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                let theme = viewModel.currentTheme(colorScheme: colorScheme)
                AnimatedGradientBackground(
                    colors: [theme.topColor, theme.bottomColor]
                )
                
                VStack(spacing: 0) {
                    // Search Bar
                    searchBar
                        .padding(.top, DesignSystem.spacingM)
                        .padding(.horizontal, DesignSystem.spacingM)
                        .padding(.bottom, DesignSystem.spacingM)
                    
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: DesignSystem.spacingL) {
                            
                            // Search Results
                            if !searchService.completions.isEmpty {
                                searchResultsSection
                            } else {
                                // Default Content
                                VStack(spacing: DesignSystem.spacingL) {
                                    // Current Location Button
                                    currentLocationButton
                                    
                                    // Favourites (if any)
                                    if !FavouritesStore.favourites.isEmpty {
                                        favouritesSection
                                    }
                                    
                                    // Recently Viewed (if any)
                                    if !RecentlyViewedStore.recentLocations.isEmpty {
                                        recentlyViewedSection
                                    }
                                }
                                .padding(.horizontal, DesignSystem.spacingM)
                            }
                        }
                        .padding(.bottom, DesignSystem.spacingXL)
                    }
                }
            }
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                            .font(.title3)
                    }
                }
            }
        }
        .preferredColorScheme(viewModel.appearanceMode == .light ? .light : viewModel.appearanceMode == .dark ? .dark : nil)
    }
    
    // MARK: - Components
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.6))
                
                TextField("", text: $searchService.searchQuery, prompt: Text("Search city, zip code...").foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.5)))
                    .focused($customCityFocused)
                    .foregroundStyle(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                    .submitLabel(.search)
                
                if !searchService.searchQuery.isEmpty {
                    Button {
                        searchService.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.7))
                            .font(.subheadline)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                    .fill(.ultraThinMaterial.opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                    .stroke(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.15), lineWidth: 0.5)
            )
        }
    }
    
    private var currentLocationButton: some View {
        Button {
            Task {
                guard !isButtonBusy else { return }
                isButtonBusy = true
                do {
                    viewModel.shouldFollowGPS = true
                    let locationData = try await locationHelper.requestLocationAndGetData()
                    await viewModel.fetchWeather(for: locationData, isManualRefresh: true)
                    dismiss()
                    
                    // Save that GPS location is being used
                    UserDefaults.standard.set(true, forKey: "Breezy.useGPSLocation")
                    UserDefaults.standard.removeObject(forKey: "Breezy.selectedLocation")
                } catch {
                    viewModel.error = "Location failed"
                }
                isButtonBusy = false
            }
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.8))
                        .frame(width: 36, height: 36)
                    Image(systemName: "location.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Location")
                        .font(.headline)
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                    Text("Using GPS")
                        .font(.caption)
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.7))
                }
                
                Spacer()
                
                if isButtonBusy {
                    ProgressView()
                        .tint(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                }
            }
            .padding(DesignSystem.spacingM)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                    .fill(.ultraThinMaterial.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                    .stroke(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.2), lineWidth: 0.5)
            )
        }
    }
    
    private var searchResultsSection: some View {
        VStack(spacing: DesignSystem.spacingS) {
            ForEach(searchService.completions, id: \.self) { completion in
                Button {
                    selectLocation(completion: completion)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title3)
                            .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.8))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(completion.title)
                                .font(.body.weight(.medium))
                                .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                            if !completion.subtitle.isEmpty {
                                Text(completion.subtitle)
                                    .font(.caption)
                                    .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.7))
                            }
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.5))
                    }
                    .padding(DesignSystem.spacingM)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(DesignSystem.radiusM)
                }
            }
        }
        .padding(.horizontal, DesignSystem.spacingM)
    }
    
    private var recentlyViewedSection: some View {
         VStack(alignment: .leading, spacing: 12) {
             Text("Recently Viewed")
                 .font(.subheadline.weight(.semibold))
                 .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.8))
             
             VStack(spacing: 8) {
                 ForEach(RecentlyViewedStore.recentLocations) { location in
                     LocationRowCard(
                         title: location.city,
                         subtitle: location.coordinateString,
                         icon: "clock.fill",
                         color: .purple,
                         textColor: viewModel.currentTheme(colorScheme: colorScheme).textColor,
                         onDelete: {
                             RecentlyViewedStore.remove(location)
                         },
                         onFavorite: FavouritesStore.favourites.contains(where: { $0.city == location.city }) ? nil : {
                             FavouritesStore.add(location)
                         }
                     ) {
                         Task {
                             viewModel.shouldFollowGPS = false
                             await viewModel.fetchWeather(for: location, isManualRefresh: true)
                             dismiss()
                         }
                     }
                 }
             }
         }
    }
    
    private var favouritesSection: some View {
         VStack(alignment: .leading, spacing: 12) {
             Text("Favourites")
                 .font(.subheadline.weight(.semibold))
                 .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.8))
             
             VStack(spacing: 8) {
                 ForEach(FavouritesStore.favourites) { location in
                     LocationRowCard(
                         title: location.city,
                         subtitle: location.coordinateString,
                         icon: "star.fill",
                         color: .yellow,
                         textColor: viewModel.currentTheme(colorScheme: colorScheme).textColor,
                         onDelete: {
                             FavouritesStore.remove(location)
                         }
                     ) {
                         Task {
                             viewModel.shouldFollowGPS = false
                             await viewModel.fetchWeather(for: location, isManualRefresh: true)
                             dismiss()
                         }
                     }
                 }
             }
         }
    }
    
    // MARK: - Actions
    
    private func selectLocation(completion: MKLocalSearchCompletion) {
        searchService.searchQuery = ""
        customCityFocused = false
        
        Task {
            do {
                viewModel.shouldFollowGPS = false
                let locationData = try await searchService.getCoordinates(for: completion)
                await viewModel.fetchWeather(for: locationData, isManualRefresh: true)
                dismiss()
                
                // Save selected location to UserDefaults
                if let encoded = try? JSONEncoder().encode(locationData) {
                    UserDefaults.standard.set(encoded, forKey: "Breezy.selectedLocation")
                }
                UserDefaults.standard.set(false, forKey: "Breezy.useGPSLocation")
            } catch {
                viewModel.error = "Could not load location details."
            }
        }
    }
}

// MARK: - Helper Views

struct LocationRowCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let textColor: Color
    var onDelete: (() -> Void)? = nil
    var onFavorite: (() -> Void)? = nil
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.caption.weight(.bold))
                        .foregroundColor(color)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundColor(textColor)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(textColor.opacity(0.6))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(textColor.opacity(0.5))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                    .fill(.ultraThinMaterial.opacity(0.3))
            )
        }
        .contextMenu {
            if let onFavorite = onFavorite {
                Button {
                    onFavorite()
                } label: {
                    Label("Add to Favourites", systemImage: "star")
                }
            }
            
            if let onDelete = onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete Location", systemImage: "trash")
                }
            }
        }
    }
}
