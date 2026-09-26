//
//  TripModeView.swift
//  Breezy
//
//  On the Way root — setup, timeline, routes, Go Now.
//

import SwiftUI

struct TripModeView: View {
    @ObservedObject var weatherViewModel: WeatherViewModel
    @ObservedObject var locationHelper: LocationHelper
    @StateObject private var tripVM = TripViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingShareCard = false

    private var theme: WeatherTheme {
        weatherViewModel.currentTheme(colorScheme: colorScheme)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground(colors: [theme.topColor, theme.bottomColor])
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DesignSystem.spacingL) {
                        if tripVM.selectedRoute != nil {
                            TripMapHeader(
                                route: tripVM.selectedRoute,
                                theme: theme,
                                glassOpacity: weatherViewModel.glassOpacity
                            )

                            if !tripVM.arrivalBrief.isEmpty {
                                Text(tripVM.arrivalBrief)
                                    .font(.headline)
                                    .foregroundStyle(theme.textColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(DesignSystem.spacingM)
                                    .background(
                                        RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                                            .fill(.ultraThinMaterial.opacity(weatherViewModel.glassOpacity))
                                    )
                            }

                            TripDepartureSlider(
                                departure: tripVM.departure,
                                range: tripVM.departureRange,
                                theme: theme,
                                glassOpacity: weatherViewModel.glassOpacity,
                                isLoadingWeather: tripVM.isLoadingWeather,
                                offlineHint: tripVM.needsWeatherRefreshHint,
                                onChange: { tripVM.departureChanged($0) }
                            )

                            if tripVM.routes.count > 1 {
                                TripRoutePicker(
                                    routes: tripVM.routes,
                                    selectedID: tripVM.selectedRouteID,
                                    theme: theme,
                                    glassOpacity: weatherViewModel.glassOpacity,
                                    onSelect: { tripVM.selectRoute($0) }
                                )
                            }

                            TripTimelineView(
                                samples: tripVM.selectedRoute?.samples ?? [],
                                theme: theme,
                                glassOpacity: weatherViewModel.glassOpacity,
                                isLoading: tripVM.isLoadingRoute || tripVM.isLoadingWeather
                            )

                            TripGoNowControls(
                                isLive: tripVM.isTripLive,
                                theme: theme,
                                glassOpacity: weatherViewModel.glassOpacity,
                                canStart: tripVM.selectedRoute != nil,
                                errorMessage: tripVM.goNowError,
                                onStart: { tripVM.startGoNow() },
                                onEnd: { tripVM.endGoNow() }
                            )
                        } else {
                            TripSetupView(
                                tripVM: tripVM,
                                weatherViewModel: weatherViewModel,
                                locationHelper: locationHelper,
                                theme: theme
                            )
                        }

                        if let error = tripVM.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, DesignSystem.spacingM)
                    .padding(.bottom, DesignSystem.spacingXXL)
                }
            }
            .navigationTitle("On the Way")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if tripVM.selectedRoute != nil {
                        Button("Edit") {
                            tripVM.endGoNow()
                            tripVM.routes = []
                            tripVM.selectedRouteID = nil
                            tripVM.arrivalBrief = ""
                            tripVM.errorMessage = nil
                            tripVM.goNowError = nil
                        }
                        .foregroundStyle(theme.textColor)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 4) {
                        if tripVM.selectedRoute != nil {
                            Button {
                                HapticsManager.shared.impact(style: .light)
                                showingShareCard = true
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundStyle(theme.textColor.opacity(0.7))
                                    .font(.body)
                            }
                        }
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(theme.textColor.opacity(0.7))
                                .font(.title3)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingShareCard) {
                if let route = tripVM.selectedRoute, let origin = tripVM.origin {
                    TripShareCardView(
                        route: route,
                        originName: origin.name,
                        destinationName: tripVM.destination?.name ?? "your destination",
                        departure: tripVM.departure,
                        arrivalBrief: tripVM.arrivalBrief,
                        theme: theme,
                        glassOpacity: weatherViewModel.glassOpacity
                    )
                }
            }
            .preferredColorScheme(weatherViewModel.appearanceMode == .light ? .light : weatherViewModel.appearanceMode == .dark ? .dark : nil)
        }
    }
}
