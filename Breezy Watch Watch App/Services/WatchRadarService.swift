//
//  WatchRadarService.swift
//  Breezy Watch Watch App
//
//  Tile compositing radar service for the watch app.
//  Builds a single composite image per frame (base map + radar overlay)
//  since watchOS's SwiftUI Map has no tile-overlay support.
//

import Foundation
import CoreLocation
import MapKit
#if canImport(UIKit)
import UIKit
import SwiftUI
#endif

// MARK: - Platform Abstractions

#if canImport(UIKit)
typealias PlatformImage = UIImage
#endif

// MARK: - RainViewer Frame Model

struct WatchRadarFrame: Identifiable, Equatable {
    let id = UUID()
    let time: Date
    let path: String
    let isNowcast: Bool
}

// MARK: - Service Errors

enum WatchRadarError: LocalizedError {
    case noLocation
    case snapshotFailed
    case tileFetchFailed
    case openWeatherKeyMissing
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noLocation: return "No location available for radar."
        case .snapshotFailed: return "Couldn't render base map."
        case .tileFetchFailed: return "Couldn't load radar tiles."
        case .openWeatherKeyMissing: return "OpenWeather API key not configured."
        case .invalidResponse: return "Radar service returned an invalid response."
        }
    }
}

// MARK: - WatchRadarService

actor WatchRadarService {
    static let shared = WatchRadarService()

    // OpenWeather tile endpoint
    private let openWeatherBaseURL = "https://tile.openweathermap.org/map"

    // RainViewer endpoints and constants
    private let rainViewerMetadataURL = URL(string: "https://api.rainviewer.com/public/weather-maps.json")!
    private let rainViewerDefaultHost = "https://tilecache.rainviewer.com"
    private let rainViewerTileSize = 256
    private let rainViewerColorScheme = 6
    private let rainViewerTileOptions = "1_1"

    // Metadata refresh interval
    private let metadataRefreshInterval: TimeInterval = 8 * 60

    // Tile grid size (3x3)
    static let gridExtent: Int = 1
    static let gridSize: Int = (gridExtent * 2 + 1)
    static let tileSize: Int = 256
    static let compositeSize: Int = tileSize * gridSize

    // Default radar zoom level for watch
    static let defaultZoom: Int = 7

    // Networking
    private let session: URLSession

    // RainViewer cached metadata
    private var cachedHost: String
    private var cachedFrames: [WatchRadarFrame]
    private var lastMetadataRefresh: Date?

    // Base map snapshot cache
    private struct SnapshotCacheKey: Hashable {
        let latitudeRounded: Int
        let longitudeRounded: Int
        let spanRounded: Int
        let isDark: Bool
    }

    private var snapshotCache: [SnapshotCacheKey: PlatformImage] = [:]

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config)
        self.cachedHost = "https://tilecache.rainviewer.com"
        self.cachedFrames = []
    }

    // MARK: - Web Mercator Math

    nonisolated func tileCoordinates(latitude: Double, longitude: Double, zoom: Int) -> (x: Int, y: Int) {
        let n = pow(2.0, Double(zoom))
        let x = Int(floor((longitude + 180.0) / 360.0 * n))
        let latRad = latitude * .pi / 180.0
        let y = Int(floor((1.0 - log(tan(latRad) + (1.0 / cos(latRad))) / .pi) / 2.0 * n))
        return (x, y)
    }

    // MARK: - Public API

    func refreshRainViewerMetadata(force: Bool = false) async throws {
        if !force,
           let lastRefresh = lastMetadataRefresh,
           Date().timeIntervalSince(lastRefresh) < metadataRefreshInterval,
           !cachedFrames.isEmpty {
            return
        }

        let (data, response) = try await session.data(from: rainViewerMetadataURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw WatchRadarError.invalidResponse
        }

        let payload = try JSONDecoder().decode(WatchRainViewerResponse.self, from: data)
        var frames: [WatchRadarFrame] = []

        if let past = payload.radar?.past {
            for frame in past {
                if let path = frame.path {
                    frames.append(WatchRadarFrame(
                        time: frame.time.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date(),
                        path: path,
                        isNowcast: false
                    ))
                }
            }
        }

        if let nowcast = payload.radar?.nowcast {
            for frame in nowcast {
                if let path = frame.path {
                    frames.append(WatchRadarFrame(
                        time: frame.time.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date(),
                        path: path,
                        isNowcast: true
                    ))
                }
            }
        }

        cachedHost = payload.host?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? rainViewerDefaultHost
        cachedFrames = frames
        lastMetadataRefresh = Date()
    }

    func availableFrames() async -> [WatchRadarFrame] {
        cachedFrames
    }

    func latestFramePath() async -> String? {
        cachedFrames.last(where: { !$0.isNowcast })?.path ?? cachedFrames.first?.path
    }

    // MARK: - Base Map Snapshot

    func fetchBaseMapSnapshot(
        center: CLLocationCoordinate2D,
        span: Double,
        isDark: Bool
    ) async throws -> PlatformImage {
        let cacheKey = SnapshotCacheKey(
            latitudeRounded: Int(center.latitude * 1000),
            longitudeRounded: Int(center.longitude * 1000),
            spanRounded: Int(span * 1000),
            isDark: isDark
        )

        if let cached = snapshotCache[cacheKey] {
            return cached
        }

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )
        options.size = CGSize(width: Self.compositeSize, height: Self.compositeSize)
        options.scale = 2.0

        let snapshotter = MKMapSnapshotter(options: options)

        let snapshot = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MKMapSnapshotter.Snapshot?, Error>) in
            snapshotter.start { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: snapshot)
                }
            }
        }

        guard let snapshot else { throw WatchRadarError.snapshotFailed }

        let image = snapshot.image
        snapshotCache[cacheKey] = image
        return image
    }

    // MARK: - Composite Image

    func fetchRadarComposite(
        center: CLLocationCoordinate2D,
        layer: WatchRadarLayer,
        source: WatchRadarPrecipitationSource,
        zoom: Int = WatchRadarService.defaultZoom,
        isDark: Bool,
        includeBaseMap: Bool,
        framePath: String? = nil
    ) async throws -> PlatformImage {
        let span = spanForZoom(zoom, latitude: center.latitude)

        let baseMap: PlatformImage?
        if includeBaseMap {
            baseMap = try await fetchBaseMapSnapshot(
                center: center,
                span: span,
                isDark: isDark
            )
        } else {
            baseMap = nil
        }

        let activeLayer: WatchRadarLayer
        let activeSource: WatchRadarPrecipitationSource

        if layer == .precipitation && source == .rainViewer {
            try await refreshRainViewerMetadata()
            activeLayer = layer
            activeSource = source
        } else if layer != .precipitation {
            activeLayer = layer
            activeSource = source
        } else {
            activeLayer = layer
            activeSource = source
        }

        let radarOverlay = try await fetchTileGridComposite(
            center: center,
            layer: activeLayer,
            source: activeSource,
            zoom: zoom,
            framePath: framePath
        )

        return stitchComposite(baseMap: baseMap, radarOverlay: radarOverlay)
    }

    // MARK: - Tile Grid Fetch

    private func fetchTileGridComposite(
        center: CLLocationCoordinate2D,
        layer: WatchRadarLayer,
        source: WatchRadarPrecipitationSource,
        zoom: Int,
        framePath: String?
    ) async throws -> PlatformImage {
        let (centerX, centerY) = tileCoordinates(latitude: center.latitude, longitude: center.longitude, zoom: zoom)
        let compositeSize = Self.compositeSize
        let tileSize = Self.tileSize

        let bitmapCtx = CGContext(
            data: nil,
            width: compositeSize,
            height: compositeSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let bitmapCtx else { throw WatchRadarError.snapshotFailed }

        let gridExtent = Self.gridExtent
        var tileFetchTasks: [(dx: Int, dy: Int, url: URL)] = []

        for dx in -gridExtent...gridExtent {
            for dy in -gridExtent...gridExtent {
                let tileX = centerX + dx
                let tileY = centerY + dy
                let n = Int(pow(2.0, Double(zoom)))
                let wrappedX = ((tileX % n) + n) % n

                guard let url = tileURL(
                    layer: layer,
                    source: source,
                    x: wrappedX,
                    y: tileY,
                    zoom: zoom,
                    framePath: framePath
                ) else { continue }

                tileFetchTasks.append((dx: dx, dy: dy, url: url))
            }
        }

        try await withThrowingTaskGroup(of: (Int, Int, PlatformImage?).self) { group in
            for task in tileFetchTasks {
                group.addTask { [weak self] in
                    guard let self else { return (task.dx, task.dy, nil) }
                    let tile = await self.fetchTile(url: task.url)
                    return (task.dx, task.dy, tile)
                }
            }

            for try await (dx, dy, tile) in group {
                guard let tile,
                      let cgTile = tile.cgImage else { continue }
                let destX = (dx + gridExtent) * tileSize
                // Tile Y axis goes top→bottom (north→south) but bitmap context Y is bottom→top
                let destYInverted = (gridExtent - dy) * tileSize
                let rect = CGRect(x: destX, y: destYInverted, width: tileSize, height: tileSize)
                bitmapCtx.draw(cgTile, in: rect)
            }
        }

        guard let composedCG = bitmapCtx.makeImage() else {
            throw WatchRadarError.snapshotFailed
        }

        return PlatformImage(cgImage: composedCG)
    }

    private func fetchTile(url: URL) async -> PlatformImage? {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return WatchRadarService.transparentTile
            }
            return PlatformImage(data: data) ?? WatchRadarService.transparentTile
        } catch {
            return WatchRadarService.transparentTile
        }
    }

    // MARK: - Tile URL Builders

    nonisolated func tileURL(
        layer: WatchRadarLayer,
        source: WatchRadarPrecipitationSource,
        x: Int,
        y: Int,
        zoom: Int,
        framePath: String?
    ) -> URL? {
        if layer == .precipitation, source == .rainViewer, let framePath {
            return rainViewerTileURL(x: x, y: y, zoom: zoom, framePath: framePath)
        }

        // OpenWeather for all non-precipitation layers + OpenWeather precip
        guard let apiKey = openWeatherAPIKey(), !apiKey.isEmpty else { return nil }
        let urlString = "\(openWeatherBaseURL)/\(layer.rawValue)/\(zoom)/\(x)/\(y).png?appid=\(apiKey)"
        return URL(string: urlString)
    }

    nonisolated private func rainViewerTileURL(x: Int, y: Int, zoom: Int, framePath: String) -> URL? {
        let path = framePath.hasPrefix("/") ? framePath : "/\(framePath)"
        let urlString = "https://tilecache.rainviewer.com\(path)/256/\(zoom)/\(x)/\(y)/6/1_1.png"
        return URL(string: urlString)
    }

    nonisolated private func openWeatherAPIKey() -> String? {
        if let key = Bundle.main.object(forInfoDictionaryKey: "OpenWeatherMapAPIKey") as? String,
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key
        }
        if let url = Bundle.main.url(forResource: "RadarSecrets", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let key = plist["OpenWeatherMapAPIKey"] as? String,
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key
        }
        return nil
    }

    // MARK: - Compositing Helpers

    private func stitchComposite(baseMap: PlatformImage?, radarOverlay: PlatformImage) -> PlatformImage {
        let width = Self.compositeSize
        let height = Self.compositeSize

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return radarOverlay
        }

        let fullRect = CGRect(x: 0, y: 0, width: width, height: height)

        if let baseMapCG = baseMap?.cgImage {
            ctx.draw(baseMapCG, in: fullRect)
        } else {
            ctx.setFillColor(red: 0.08, green: 0.1, blue: 0.14, alpha: 1)
            ctx.fill(fullRect)
        }

        if let radarCG = radarOverlay.cgImage {
            ctx.setAlpha(0.85)
            ctx.draw(radarCG, in: fullRect)
        }

        guard let composedCG = ctx.makeImage() else {
            return radarOverlay
        }
        return PlatformImage(cgImage: composedCG)
    }

    private func spanForZoom(_ zoom: Int, latitude: Double) -> Double {
        let n = pow(2.0, Double(zoom))
        let earthCircumferenceDegrees = 360.0
        let tileSizeDegrees = earthCircumferenceDegrees / n
        return tileSizeDegrees * Double(Self.gridSize) * cos(latitude * .pi / 180.0)
    }

    // MARK: - Transparent Fallback Tile

    static let transparentTile: PlatformImage = {
        let width = 256
        let height = 256
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = ctx.makeImage() else {
            return PlatformImage()
        }
        return PlatformImage(cgImage: cgImage)
    }()
}

// MARK: - RainViewer Response Models

private struct WatchRainViewerResponse: Decodable {
    let host: String?
    let radar: WatchRainViewerFrames?
}

private struct WatchRainViewerFrames: Decodable {
    let past: [WatchRainViewerFrameDTO]?
    let nowcast: [WatchRainViewerFrameDTO]?
}

private struct WatchRainViewerFrameDTO: Decodable {
    let path: String?
    let time: Int?
}
