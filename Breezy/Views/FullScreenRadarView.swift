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
    var locationHelper: LocationHelper? = nil
    @State private var selectedLayer: RadarLayer = .precipitation
    @State private var region: MKCoordinateRegion
    @State private var showLayerMenu = false
    @State private var isLoading = true

    private let defaultSpan = MKCoordinateSpan(latitudeDelta: 5.0, longitudeDelta: 5.0)

    private var currentCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: viewModel.currentLocation?.latitude ?? 0,
            longitude: viewModel.currentLocation?.longitude ?? 0
        )
    }

    private var hasMovedMap: Bool {
        let currentLocation = CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude)
        let mapCenter = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let distanceFromOrigin = currentLocation.distance(from: mapCenter)
        let latitudeChanged = abs(region.span.latitudeDelta - defaultSpan.latitudeDelta) > 0.15
        let longitudeChanged = abs(region.span.longitudeDelta - defaultSpan.longitudeDelta) > 0.15

        return distanceFromOrigin > 1500 || latitudeChanged || longitudeChanged
    }
    
    init(viewModel: WeatherViewModel, locationHelper: LocationHelper? = nil) {
        self.viewModel = viewModel
        self.locationHelper = locationHelper
        
        let initialCoordinate = CLLocationCoordinate2D(
            latitude: viewModel.currentLocation?.latitude ?? 0,
            longitude: viewModel.currentLocation?.longitude ?? 0
        )
        
        _region = State(initialValue: MKCoordinateRegion(
            center: initialCoordinate,
            span: defaultSpan
        ))
    }
    
    var body: some View {
        let theme = viewModel.currentTheme(colorScheme: colorScheme)

        ZStack {
            RadarMapView(
                region: $region,
                layer: selectedLayer,
                isLoading: $isLoading,
                coordinate: currentCoordinate,
                isDark: theme.isDark,
                mapStyle: viewModel.mapStyle
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(theme.isDark ? 0.42 : 0.22), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 180)

                Spacer()

                LinearGradient(
                    colors: [.clear, Color.black.opacity(theme.isDark ? 0.36 : 0.18)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 220)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if !isLoading {
                VStack {
                    Spacer()

                    HStack(alignment: .bottom) {
                        RadarLegendView(layer: selectedLayer)

                        Spacer()

                        if hasMovedMap {
                            Button {
                                HapticsManager.shared.impact(style: .light)
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                                    region.center = currentCoordinate
                                    region.span = defaultSpan
                                }
                            } label: {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if isLoading {
                VStack {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)

                        Text("Loading radar")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())

                    Spacer()
                }
                .padding(.top, 112)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
            }
        }
        .safeAreaInset(edge: .top) {
            HStack(spacing: 12) {
                Button {
                    HapticsManager.shared.impact(style: .light)
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 42, height: 42)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.currentLocation?.city ?? "Weather Radar")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(selectedLayer.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white.opacity(0.78))
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Spacer(minLength: 8)

                Menu {
                    Picker("Map Style", selection: $viewModel.mapStyle) {
                        ForEach(WeatherViewModel.RadarMapStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                } label: {
                    Image(systemName: "map.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 42, height: 42)
                }
                .onChange(of: viewModel.mapStyle) { _, _ in
                    HapticsManager.shared.selectionChanged()
                }

                Button {
                    HapticsManager.shared.impact(style: .light)
                    showLayerMenu = true
                } label: {
                    Image(systemName: "square.3.layers.3d.down.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 42, height: 42)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)
        }
        .sheet(isPresented: $showLayerMenu) {
            RadarLayerMenuView(selectedLayer: $selectedLayer)
        }
        .onChange(of: selectedLayer) { oldValue, newValue in
            HapticsManager.shared.impact(style: .light)
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
