//
//  FullScreenRadarView.swift
//  Breezy
//
//  Full-screen radar modal view
//

import SwiftUI
import MapKit

struct FullScreenRadarView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedLayer: RadarLayer = .precipitation
    @State private var region: MKCoordinateRegion
    @State private var showLayerMenu = false
    @State private var isLoading = true
    
    init(viewModel: WeatherViewModel) {
        self.viewModel = viewModel
        
        let initialCoordinate = CLLocationCoordinate2D(
            latitude: viewModel.currentLocation?.latitude ?? 0,
            longitude: viewModel.currentLocation?.longitude ?? 0
        )
        
        _region = State(initialValue: MKCoordinateRegion(
            center: initialCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 5.0, longitudeDelta: 5.0)
        ))
    }
    
    var body: some View {
        ZStack {
            // Background gradient matching theme
            let theme = viewModel.currentTheme(colorScheme: colorScheme)
            AnimatedGradientBackground(colors: [theme.topColor, theme.bottomColor])
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Weather Radar")
                            .font(.title2.bold())
                            .foregroundColor(theme.textColor)
                        
                        if let city = viewModel.currentLocation?.city {
                            Text(city)
                                .font(.subheadline)
                                .foregroundColor(theme.textColor.opacity(0.7))
                        }
                    }
                    
                    Spacer()
                    
                    
                    // Map Style Button
                    Menu {
                        Picker("Map Style", selection: $viewModel.mapStyle) {
                            ForEach(WeatherViewModel.RadarMapStyle.allCases) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                    } label: {
                        Image(systemName: "map.fill")
                            .font(.title2)
                            .foregroundColor(theme.textColor)
                            .padding(8)
                            .background(Circle().fill(Color.white.opacity(0.2)))
                    }

                    // Layer button
                    Button {
                        showLayerMenu = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: selectedLayer.icon)
                            Text(selectedLayer.displayName)
                            Image(systemName: "chevron.down")
                        }
                        .font(.callout.weight(.semibold))
                        .foregroundColor(theme.textColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                        )
                    }
                    
                    // Close button
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(theme.textColor)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                .padding()
                
                // Map
                ZStack {
                    RadarMapView(
                        region: $region,
                        layer: selectedLayer,
                        isLoading: $isLoading,
                        coordinate: CLLocationCoordinate2D(
                            latitude: viewModel.currentLocation?.latitude ?? 0,
                            longitude: viewModel.currentLocation?.longitude ?? 0
                        ),
                        isDark: viewModel.currentTheme(colorScheme: colorScheme).isDark,
                        mapStyle: viewModel.mapStyle
                    )
                    .cornerRadius(DesignSystem.radiusL)
                    .padding(.horizontal)
                    
                    // Loading indicator
                    if isLoading {
                        ZStack {
                            Color.black.opacity(0.3)
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.white)
                                Text("Loading radar...")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                            }
                        }
                        .cornerRadius(DesignSystem.radiusL)
                        .padding(.horizontal)
                    }
                    
                    // Legend (top right) - compact version
                    if !isLoading {
                        VStack {
                            HStack {
                                Spacer()
                                RadarLegendView(layer: selectedLayer)
                                    .padding(.trailing, 20)
                            }
                            Spacer()
                        }
                        .padding(.top, 16)
                    }
                }
                .frame(maxHeight: .infinity)
                .padding(.bottom)
            }
        }
        .sheet(isPresented: $showLayerMenu) {
            RadarLayerMenuView(selectedLayer: $selectedLayer)
        }
        .onChange(of: selectedLayer) { oldValue, newValue in
            isLoading = true
        }
        .onChange(of: viewModel.currentLocation) { oldValue, newLocation in
            if let location = newLocation {
                withAnimation {
                    region.center = CLLocationCoordinate2D(
                        latitude: location.latitude,
                        longitude: location.longitude
                    )
                }
            }
        }
    }
}
