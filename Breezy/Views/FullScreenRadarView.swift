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

    // Animation state
    @State private var frames: [RadarService.RainViewerFrameData] = []
    @State private var currentFrameIndex: Int = 0
    @State private var isPlaying: Bool = false
    @State private var animationTimer: Timer?
    @State private var metadataLoaded: Bool = false
    @State private var isScrubbing: Bool = false

    private var precipitationSource: RadarPrecipitationSource {
        viewModel.radarPrecipitationSource
    }

    private var canAnimate: Bool {
        selectedLayer == .precipitation && precipitationSource == .rainViewer && !frames.isEmpty
    }

    private var activeFramePath: String? {
        guard canAnimate, frames.indices.contains(currentFrameIndex) else { return nil }
        return frames[currentFrameIndex].path
    }

    private var activeFrameTime: Date? {
        guard canAnimate, frames.indices.contains(currentFrameIndex) else { return nil }
        return frames[currentFrameIndex].time
    }

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
                precipitationSource: precipitationSource,
                isLoading: $isLoading,
                coordinate: currentCoordinate,
                isDark: theme.isDark,
                mapStyle: viewModel.mapStyle,
                framePath: activeFramePath
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

                    // Playback controls (only for RainViewer precipitation)
                    if canAnimate {
                        VStack(spacing: 8) {
                            // Timeline scrubber
                            HStack(spacing: 8) {
                                Button {
                                    HapticsManager.shared.impact(style: .light)
                                    togglePlayback()
                                } label: {
                                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 36, height: 36)
                                        .background(Color.white.opacity(0.18), in: Circle())
                                }

                                VStack(spacing: 2) {
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule()
                                                .fill(Color.white.opacity(0.22))
                                                .frame(height: 4)

                                            Capsule()
                                                .fill(Color.white)
                                                .frame(width: max(0, geo.size.width * CGFloat(frames.isEmpty ? 0 : currentFrameIndex) / max(1, CGFloat(frames.count - 1))), height: 4)
                                        }
                                        .frame(height: 24)
                                        .contentShape(Rectangle())
                                        .gesture(
                                            DragGesture(minimumDistance: 0)
                                                .onChanged { value in
                                                    if !isScrubbing {
                                                        isScrubbing = true
                                                        pauseAnimation()
                                                    }
                                                    let fraction = max(0, min(1, value.location.x / geo.size.width))
                                                    let newIndex = Int(round(fraction * CGFloat(max(0, frames.count - 1))))
                                                    if newIndex != currentFrameIndex {
                                                        HapticsManager.shared.selectionChanged()
                                                        currentFrameIndex = newIndex
                                                    }
                                                }
                                                .onEnded { _ in
                                                    isScrubbing = false
                                                }
                                        )
                                    }
                                    .frame(height: 24)

                                    HStack {
                                        Text("-3h")
                                            .font(.system(size: 9, weight: .medium))
                                        Spacer()
                                        if let time = activeFrameTime {
                                            Text(time, style: .time)
                                                .font(.system(size: 10, weight: .semibold))
                                        }
                                        Spacer()
                                        Text("+2h")
                                            .font(.system(size: 9, weight: .medium))
                                    }
                                    .foregroundColor(.white.opacity(0.75))
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    HStack(alignment: .bottom) {
                        RadarLegendView(layer: selectedLayer, precipitationSource: precipitationSource)

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
            RadarLayerMenuView(selectedLayer: $selectedLayer, precipitationSource: precipitationSource)
        }
        .onChange(of: precipitationSource) { _, _ in
            isLoading = true
            pauseAnimation()
            frames = []
            currentFrameIndex = 0
            metadataLoaded = false
            loadFramesIfNeeded()
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
        .onAppear {
            loadFramesIfNeeded()
        }
        .onDisappear {
            pauseAnimation()
        }
        .onChange(of: selectedLayer) { _, newLayer in
            // Start playback automatically when entering precipitation RainViewer
            if newLayer == .precipitation && precipitationSource == .rainViewer {
                loadFramesIfNeeded()
            } else {
                pauseAnimation()
                frames = []
                currentFrameIndex = 0
            }
        }
    }

    // MARK: - Animation

    private func loadFramesIfNeeded() {
        guard selectedLayer == .precipitation,
              precipitationSource == .rainViewer,
              !metadataLoaded else { return }

        metadataLoaded = true
        RadarService.shared.refreshRainViewerMetadataIfNeeded(force: true) {
            DispatchQueue.main.async {
                let fresh = RadarService.shared.rainViewerFrames
                self.frames = fresh
                if !fresh.isEmpty {
                    // Default to the latest past frame
                    self.currentFrameIndex = max(0, fresh.lastIndex(where: { !$0.isNowcast }) ?? fresh.count - 1)
                }
            }
        }
    }

    private func togglePlayback() {
        if isPlaying {
            pauseAnimation()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        guard canAnimate else { return }
        pauseAnimation()
        isPlaying = true

        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            DispatchQueue.main.async {
                guard !self.frames.isEmpty else { return }
                let next = (self.currentFrameIndex + 1) % self.frames.count
                if next != self.currentFrameIndex {
                    self.currentFrameIndex = next
                }
            }
        }
    }

    private func pauseAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        isPlaying = false
    }
}
