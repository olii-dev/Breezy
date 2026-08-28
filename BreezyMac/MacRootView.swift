//
//  MacRootView.swift
//  BreezyMac
//
//  Root split view: locations sidebar + themed dashboard detail.
//

import SwiftUI

/// App-wide shared engine instances so the main window, extra location
/// windows, and the Settings window all observe the same state.
enum MacShared {
    static let viewModel = WeatherViewModel()
    static let locationHelper = LocationHelper()
}

struct MacRootView: View {
    @ObservedObject private var viewModel = MacShared.viewModel
    @ObservedObject private var locationHelper = MacShared.locationHelper
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("Breezy.HasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var favourites: [LocationData] = []
    @State private var recents: [LocationData] = []
    @State private var selection: SidebarItem? = .current
    @State private var showFirstRun = false
    @State private var showTimeMachine = false
    @State private var showRadar = false
    @State private var showLocationPicker = false

    enum SidebarItem: Hashable {
        case current
        case location(LocationData)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            detail
        }
        .sheet(isPresented: $showFirstRun) {
            MacFirstRunView(isPresented: $showFirstRun, viewModel: viewModel, locationHelper: locationHelper)
        }
        .sheet(isPresented: $showTimeMachine) {
            TimeMachineView(viewModel: viewModel)
        }
        .sheet(isPresented: $showRadar) {
            FullScreenRadarView(viewModel: viewModel, locationHelper: locationHelper)
        }
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerView(viewModel: viewModel, locationHelper: locationHelper, isButtonBusy: .constant(false))
        }
        .onAppear {
            reloadLocationLists()
            if hasCompletedOnboarding {
                viewModel.performStartupIfNeeded(locationHelper: locationHelper)
            } else {
                showFirstRun = true
            }
        }
        .onChange(of: hasCompletedOnboarding) { _, done in
            if done {
                viewModel.performStartupIfNeeded(locationHelper: locationHelper)
            }
        }
        .onChange(of: viewModel.currentLocation) { _, _ in
            reloadLocationLists()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macTimeMachineRequested)) { _ in
            showTimeMachine = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .macRadarRequested)) { _ in
            showRadar = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .macRefreshRequested)) { _ in
            refresh()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Weather") {
                Label(viewModel.currentLocation?.city ?? "Current Location", systemImage: "location.fill")
                    .tag(SidebarItem.current)
            }

            if !favourites.isEmpty {
                Section("Favourites") {
                    ForEach(favourites) { location in
                        Label(location.city, systemImage: "star.fill")
                            .tag(SidebarItem.location(location))
                            .contextMenu {
                                Button("Open in New Window") {
                                    openWindow(id: "location", value: location)
                                }
                                Button("Remove from Favourites", role: .destructive) {
                                    FavouritesStore.remove(location)
                                    reloadLocationLists()
                                }
                            }
                    }
                }
            }

            if !recents.isEmpty {
                Section("Recently Viewed") {
                    ForEach(recents) { location in
                        Label(location.city, systemImage: "clock")
                            .tag(SidebarItem.location(location))
                            .contextMenu {
                                Button("Open in New Window") {
                                    openWindow(id: "location", value: location)
                                }
                                Button("Add to Favourites") {
                                    FavouritesStore.add(location)
                                    reloadLocationLists()
                                }
                                Button("Remove", role: .destructive) {
                                    RecentlyViewedStore.remove(location)
                                    reloadLocationLists()
                                }
                            }
                    }
                }
            }

            Section {
                Button {
                    showTimeMachine = true
                } label: {
                    Label("Time Machine", systemImage: "hourglass")
                }
                Button {
                    Task {
                        await NotificationManager.shared.requestAuthorization()
                    }
                } label: {
                    Label("Notification Settings", systemImage: "bell.badge")
                }
            }
        }
        .listStyle(.sidebar)
        .onChange(of: selection) { _, newValue in
            handleSelection(newValue)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        let theme = viewModel.currentTheme(colorScheme: colorScheme)

        ZStack {
            PastelGradientBackground(colors: [theme.topColor, theme.bottomColor])

            if viewModel.isLoading && viewModel.weather == nil {
                ProgressView("Fetching weather…")
                    .tint(theme.textColor)
            } else if let weather = viewModel.weather {
                MacDashboardView(
                    viewModel: viewModel,
                    locationHelper: locationHelper,
                    onPickLocation: { showLocationPicker = true }
                )
            } else if let error = viewModel.error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.icloud")
                        .font(.system(size: 40))
                        .foregroundColor(theme.textColor.opacity(0.6))
                    Text(error)
                        .font(.headline)
                        .foregroundColor(theme.textColor)
                    Button("Try Again") {
                        refresh()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(40)
            }
        }
    }

    // MARK: - Actions

    private func handleSelection(_ item: SidebarItem?) {
        guard let item else { return }
        switch item {
        case .current:
            refresh()
        case .location(let location):
            viewModel.shouldFollowGPS = false
            Task {
                await viewModel.fetchWeather(for: location, isManualRefresh: true)
            }
        }
    }

    private func refresh() {
        Task {
            if let current = viewModel.currentLocation, !viewModel.shouldFollowGPS {
                await viewModel.fetchWeather(for: current, isManualRefresh: true)
            } else if let gps = try? await locationHelper.requestLocationAndGetData() {
                await viewModel.fetchWeather(for: gps, isManualRefresh: true)
            } else if let current = viewModel.currentLocation {
                await viewModel.fetchWeather(for: current, isManualRefresh: true)
            }
            reloadLocationLists()
        }
    }

    private func reloadLocationLists() {
        favourites = FavouritesStore.favourites
        recents = RecentlyViewedStore.recentLocations
    }
}

/// A standalone window pinned to one location (File → New Window on a row).
struct MacLocationWindowView: View {
    let location: LocationData?

    @ObservedObject private var viewModel = MacShared.viewModel
    @ObservedObject private var locationHelper = MacShared.locationHelper
    @Environment(\.colorScheme) private var colorScheme
    @State private var didFetch = false

    var body: some View {
        Group {
            if let location {
                MacDashboardView(viewModel: viewModel, locationHelper: locationHelper, onPickLocation: {})
                    .task {
                        guard !didFetch else { return }
                        didFetch = true
                        viewModel.shouldFollowGPS = false
                        await viewModel.fetchWeather(for: location, isManualRefresh: true)
                    }
            } else {
                Text("No location selected.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
