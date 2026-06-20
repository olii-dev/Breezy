//
//  WatchRadarView.swift
//  Breezy Watch Watch App
//
//  Composite-image radar view with animation and crown scrubber.
//

import SwiftUI
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Main Radar View

struct WatchRadarView: View {
    @EnvironmentObject var viewModel: WatchWeatherViewModel
    @Environment(\.colorScheme) var colorScheme

    @State private var compositeImage: PlatformImage?
    @State private var frames: [WatchRadarFrame] = []
    @State private var currentFrameIndex: Int = 0
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showLayerPicker: Bool = false
    @State private var animationTask: Task<Void, Never>?

    @AppStorage(WatchAppStorageKey.radarLayer, store: UserDefaults(suiteName: WatchAppStorageKey.appGroup))
    private var selectedLayerRaw: String = WatchRadarLayer.precipitation.rawValue

    @AppStorage(WatchAppStorageKey.radarShowBaseMap, store: UserDefaults(suiteName: WatchAppStorageKey.appGroup))
    private var showBaseMap: Bool = true

    @AppStorage(WatchAppStorageKey.radarShowLegend, store: UserDefaults(suiteName: WatchAppStorageKey.appGroup))
    private var showLegend: Bool = true

    @AppStorage(WatchAppStorageKey.radarAnimationEnabled, store: UserDefaults(suiteName: WatchAppStorageKey.appGroup))
    private var animationEnabled: Bool = true

    @State private var isPlaying: Bool = false
    @State private var crownValue: Double = 0

    private var selectedLayer: WatchRadarLayer {
        WatchRadarLayer(rawValue: selectedLayerRaw) ?? .precipitation
    }

    private var selectedSource: WatchRadarPrecipitationSource {
        let defaults = UserDefaults(suiteName: WatchAppStorageKey.appGroup)
        let raw = defaults?.string(forKey: WatchAppStorageKey.radarPrecipitationSource) ?? WatchRadarPrecipitationSource.rainViewer.rawValue
        return WatchRadarPrecipitationSource(rawValue: raw) ?? .rainViewer
    }

    private var radarCenter: CLLocationCoordinate2D? {
        guard let lat = viewModel.weather?.metadata.latitude,
              let lon = viewModel.weather?.metadata.longitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var body: some View {
        let theme = viewModel.currentTheme(isSystemDark: colorScheme == .dark)

        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [theme.topColor, theme.bottomColor]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 6) {
                headerRow(theme: theme)

                radarImage(theme: theme)
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(theme.textColor.opacity(0.15), lineWidth: 0.5)
                    )

                if showLegend {
                    WatchRadarLegendBar(
                        layer: selectedLayer,
                        source: selectedSource,
                        textColor: theme.textColor
                    )
                    .transition(.opacity)
                }

                if animationEnabled && !frames.isEmpty {
                    playbackControls(theme: theme)
                }
            }
            .padding(.horizontal, 6)
        }
        .navigationTitle {
            Text("Radar")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.playHaptic(.click)
                    showLayerPicker = true
                } label: {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(theme.textColor)
                }
            }
        }
        .sheet(isPresented: $showLayerPicker) {
            WatchRadarSettingsSheet(
                selectedLayerRaw: $selectedLayerRaw,
                showBaseMap: $showBaseMap,
                showLegend: $showLegend,
                animationEnabled: $animationEnabled,
                theme: theme
            )
        }
        .task {
            await loadRadar()
        }
        .onChange(of: selectedLayerRaw) { _, _ in
            Task { await loadRadar() }
        }
        .onChange(of: radarCenter?.latitude) { _, _ in
            Task { await loadRadar() }
        }
        .onDisappear {
            stopAnimation()
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func headerRow(theme: WatchWeatherTheme) -> some View {
        HStack(spacing: 6) {
            Image(systemName: selectedLayer.iconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(theme.textColor.opacity(0.85))

            Text(viewModel.weather?.city ?? "Radar")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer()

            if let frame = currentFrame() {
                Text(frame.time, style: .time)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(theme.textColor.opacity(0.6))
            }
        }
    }

    // MARK: - Radar Image

    @ViewBuilder
    private func radarImage(theme: WatchWeatherTheme) -> some View {
        ZStack {
            if let composite = compositeImage {
                Image(uiImage: composite)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else if isLoading {
                VStack(spacing: 6) {
                    ProgressView()
                        .tint(theme.textColor)
                    Text("Loading radar")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(theme.textColor.opacity(0.6))
                }
            } else if let errorMessage {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.yellow)
                    Text(errorMessage)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(theme.textColor.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 8)
            } else {
                Image(systemName: selectedLayer.iconName)
                    .font(.system(size: 30))
                    .foregroundColor(theme.textColor.opacity(0.3))
            }

            // Location dot at center
            if compositeImage != nil {
                WatchRadarLocationDot(color: theme.textColor)
            }
        }
    }

    // MARK: - Playback Controls

    @ViewBuilder
    private func playbackControls(theme: WatchWeatherTheme) -> some View {
        HStack(spacing: 8) {
            Button {
                viewModel.playHaptic(.click)
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(theme.textColor)
                    .frame(width: 28, height: 28)
                    .background(theme.textColor.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)

            // Frame scrubber
            HStack(spacing: 3) {
                ForEach(Array(frames.enumerated()), id: \.element.id) { index, frame in
                    Capsule()
                        .fill(index == currentFrameIndex ? theme.textColor : theme.textColor.opacity(0.25))
                        .frame(height: 12)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 14)
            .padding(.horizontal, 4)
            .background(theme.textColor.opacity(0.08), in: Capsule())
            .digitalCrownRotation(
                $crownValue,
                from: 0,
                through: Double(max(frames.count - 1, 0)),
                by: 1,
                sensitivity: .medium,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
            .onChange(of: crownValue) { _, newValue in
                let newIndex = Int(newValue.rounded())
                guard newIndex != currentFrameIndex else { return }
                currentFrameIndex = newIndex
                Task { await renderFrame(at: newIndex) }
            }
        }
    }

    // MARK: - Data Loading

    private func loadRadar() async {
        guard let center = radarCenter else {
            errorMessage = "No location available"
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            if selectedLayer == .precipitation && selectedSource == .rainViewer {
                try await WatchRadarService.shared.refreshRainViewerMetadata()
                frames = await WatchRadarService.shared.availableFrames()
                currentFrameIndex = max(frames.count - 1, 0)
            } else {
                frames = []
            }

            let framePath = animationEnabled ? frames.last?.path : nil
            let image = try await WatchRadarService.shared.fetchRadarComposite(
                center: center,
                layer: selectedLayer,
                source: selectedSource,
                isDark: colorScheme == .dark,
                includeBaseMap: showBaseMap,
                framePath: framePath
            )

            await MainActor.run {
                self.compositeImage = image
                self.isLoading = false

                if animationEnabled && !frames.isEmpty && !isPlaying {
                    startAnimation()
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func renderFrame(at index: Int) async {
        guard let center = radarCenter,
              frames.indices.contains(index) else { return }

        let framePath = frames[index].path
        do {
            let image = try await WatchRadarService.shared.fetchRadarComposite(
                center: center,
                layer: selectedLayer,
                source: selectedSource,
                isDark: colorScheme == .dark,
                includeBaseMap: showBaseMap,
                framePath: framePath
            )
            await MainActor.run {
                self.compositeImage = image
            }
        } catch {
            // Silent fail on individual frames
        }
    }

    private func currentFrame() -> WatchRadarFrame? {
        frames.indices.contains(currentFrameIndex) ? frames[currentFrameIndex] : frames.last
    }

    // MARK: - Animation

    private func togglePlayback() {
        if isPlaying {
            stopAnimation()
        } else {
            startAnimation()
        }
    }

    private func startAnimation() {
        guard animationEnabled, !frames.isEmpty else { return }
        stopAnimation()
        isPlaying = true

        animationTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { break }

                await MainActor.run {
                    currentFrameIndex = (currentFrameIndex + 1) % frames.count
                }

                await renderFrame(at: currentFrameIndex)
            }
        }
    }

    private func stopAnimation() {
        animationTask?.cancel()
        animationTask = nil
        isPlaying = false
    }
}

// MARK: - Location Dot

private struct WatchRadarLocationDot: View {
    let color: Color
    @State private var animatePulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(animatePulse ? 0.0 : 0.35))
                .frame(width: animatePulse ? 22 : 10, height: animatePulse ? 22 : 10)

            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: .black.opacity(0.5), radius: 2)

            Circle()
                .stroke(.white.opacity(0.7), lineWidth: 1)
                .frame(width: 8, height: 8)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: true)) {
                animatePulse = true
            }
        }
    }
}

// MARK: - Legend Bar

struct WatchRadarLegendBar: View {
    let layer: WatchRadarLayer
    let source: WatchRadarPrecipitationSource
    let textColor: Color

    private var gradient: [(value: Double, hexColor: String, label: String)] {
        layer.legendGradient(for: source)
    }

    private var normalizedStops: [Gradient.Stop] {
        let values = gradient.map { $0.value }
        guard let min = values.min(), let max = values.max(), max > min else {
            return []
        }
        return gradient.map { item in
            Gradient.Stop(color: WatchColorFromHex(item.hexColor) ?? textColor, location: (item.value - min) / (max - min))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            LinearGradient(stops: normalizedStops, startPoint: .leading, endPoint: .trailing)
                .frame(height: 6)
                .clipShape(Capsule())

            HStack {
                Text(gradient.first?.label ?? "")
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                Spacer()
                Text(gradient.last?.label ?? "")
                    .font(.system(size: 8, weight: .medium, design: .rounded))
            }
            .foregroundColor(textColor.opacity(0.7))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(textColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Settings Sheet

struct WatchRadarSettingsSheet: View {
    @Binding var selectedLayerRaw: String
    @Binding var showBaseMap: Bool
    @Binding var showLegend: Bool
    @Binding var animationEnabled: Bool
    let theme: WatchWeatherTheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("RADAR OPTIONS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(theme.textColor.opacity(0.6))

                VStack(spacing: 4) {
                    ForEach(WatchRadarLayer.allCases) { layer in
                        Button {
                            selectedLayerRaw = layer.rawValue
                        } label: {
                            HStack {
                                Image(systemName: layer.iconName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(theme.textColor)
                                    .frame(width: 20)

                                Text(layer.displayName)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(theme.textColor)

                                Spacer()

                                if selectedLayerRaw == layer.rawValue {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(theme.textColor)
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(theme.textColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider().background(theme.textColor.opacity(0.15))

                Toggle(isOn: $showBaseMap) {
                    Label("Base Map", systemImage: "map.fill")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(theme.textColor)
                }
                .tint(theme.textColor)

                Toggle(isOn: $showLegend) {
                    Label("Legend", systemImage: "paintpalette")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(theme.textColor)
                }
                .tint(theme.textColor)

                Toggle(isOn: $animationEnabled) {
                    Label("Animation", systemImage: "play.circle.fill")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(theme.textColor)
                }
                .tint(theme.textColor)

                if selectedLayerRaw == WatchRadarLayer.precipitation.rawValue {
                    Divider().background(theme.textColor.opacity(0.15))

                    Text("Precipitation source is synced from your iPhone settings.")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(theme.textColor.opacity(0.5))
                }
            }
            .padding(.horizontal, 4)
        }
        .background(theme.bottomColor.opacity(0.4).ignoresSafeArea())
    }
}

// MARK: - Color Helper

private func WatchColorFromHex(_ hex: String) -> Color? {
    var sanitized = hex
    if sanitized.hasPrefix("#") {
        sanitized.removeFirst()
    }
    guard sanitized.count == 8 || sanitized.count == 6 else { return nil }
    var rgb: UInt64 = 0
    Scanner(string: sanitized).scanHexInt64(&rgb)
    let r, g, b, a: Double
    if sanitized.count == 8 {
        r = Double((rgb & 0xFF000000) >> 24) / 255
        g = Double((rgb & 0x00FF0000) >> 16) / 255
        b = Double((rgb & 0x0000FF00) >> 8) / 255
        a = Double(rgb & 0x000000FF) / 255
    } else {
        r = Double((rgb & 0xFF0000) >> 16) / 255
        g = Double((rgb & 0x00FF00) >> 8) / 255
        b = Double(rgb & 0x0000FF) / 255
        a = 1
    }
    return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
}
