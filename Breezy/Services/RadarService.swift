//
//  RadarService.swift
//  Breezy
//
//  Radar tile service for OpenWeather + RainViewer overlays
//

import Foundation
import CoreLocation
import MapKit
import UIKit

enum RadarPrecipitationSource: String, CaseIterable, Identifiable {
    case rainViewer = "RainViewer"
    case openWeather = "OpenWeather"

    static let storageKey = "Breezy.radarPrecipitationSource"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var subtitle: String {
        switch self {
        case .rainViewer:
            return "Global precipitation radar tiles. Best for live rain coverage."
        case .openWeather:
            return "OpenWeather precipitation layer. Matches Breezy's other weather map layers."
        }
    }
}

enum RadarLayer: String, CaseIterable, Identifiable {
    case precipitation = "precipitation_new"
    case wind = "wind_new"
    case clouds = "clouds_new"
    case temperature = "temp_new"
    case pressure = "pressure_new"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .precipitation: return "Precipitation"
        case .wind: return "Wind Speed"
        case .clouds: return "Clouds"
        case .temperature: return "Temperature"
        case .pressure: return "Sea Level Pressure"
        }
    }
    
    var icon: String {
        switch self {
        case .precipitation: return "cloud.rain.fill"
        case .wind: return "wind"
        case .clouds: return "cloud.fill"
        case .temperature: return "thermometer.medium"
        case .pressure: return "gauge.medium"
        }
    }
    
    func legendGradient(for precipitationSource: RadarPrecipitationSource) -> [(value: Double, color: String, label: String)] {
        switch self {
        case .precipitation:
            if precipitationSource == .rainViewer {
                return [
                    (0, "#00000000", "Light"),
                    (20, "#6CCB5F", ""),
                    (40, "#F3D250", ""),
                    (60, "#F58B2A", ""),
                    (80, "#E34A4A", ""),
                    (100, "#B7349B", "Heavy")
                ]
            } else {
                // mm/hr - OpenWeather scale
                return [
                    (0, "#00000000", "0"),
                    (0.1, "#C89696", "0.1"),
                    (0.5, "#7878BE", "0.5"),
                    (1, "#6E6ECD", "1"),
                    (10, "#5050E1", "10"),
                    (50, "#1414FF", "50+ mm/h")
                ]
            }
        case .wind:
            // m/s - Official OWM scale
            return [
                (0, "#FFFFFF00", "0"),
                (5, "#EECECECC", "5"),
                (15, "#B364BC", "15"),
                (25, "#3F213B", "25"),
                (50, "#744CAC", "50"),
                (100, "#4600AF", "100+ m/s")
            ]
        case .clouds:
            return [
                (0, "#FFFFFF00", "0"),
                (10, "#FFFFFF33", "10"),
                (30, "#FFFFFF66", "30"),
                (50, "#FFFFFF99", "50"),
                (70, "#FFFFFFCC", "70"),
                (100, "#FFFFFFFF", "100%")
            ]
        case .temperature:
            return [
                (-40, "#821692", "-40"),
                (-20, "#8257DB", "-20"),
                (0, "#2080E1", "0"),
                (20, "#FCE702", "20"),
                (40, "#FF8C00", "40"),
                (60, "#FF0000", "60°C")
            ]
        case .pressure:
            return [
                (950, "#0000FF", "950"),
                (980, "#00FFFF", "980"),
                (1013, "#00FF00", "1013"),
                (1040, "#FFFF00", "1040"),
                (1070, "#FF0000", "1070 hPa")
            ]
        }
    }
}

class RadarService {
    static let shared = RadarService()
    private let openWeatherBaseURL = "https://tile.openweathermap.org/map"
    private let rainViewerMetadataURL = URL(string: "https://api.rainviewer.com/public/weather-maps.json")!
    private let rainViewerDefaultHost = "https://tilecache.rainviewer.com"
    private let rainViewerTileSize = 256

    /// Public RainViewer frame model (path + time)
    struct RainViewerFrameData: Identifiable, Equatable {
        let id = UUID()
        let path: String
        let time: Date
        let isNowcast: Bool
    }

    /// Time range for radar animation (in minutes from current time)
    static let pastTimeRange: Int = 180  // 3 hours back
    static let futureTimeRange: Int = 120 // 2 hours forward
    private let rainViewerColorScheme = 6
    private let rainViewerTileOptions = "1_1"
    private let rainViewerRefreshInterval: TimeInterval = 8 * 60
    private let apiKey: String
    private let session: URLSession
    private let stateQueue = DispatchQueue(label: "com.breezy.radar.service")
    private var cachedRainViewerHost: String?
    private var cachedRainViewerFramePath: String?
    private var cachedRainViewerFrames: [RainViewerFrameData] = []
    private var lastRainViewerRefresh: Date?
    private var isRefreshingRainViewer = false
    private var pendingRainViewerCompletions: [() -> Void] = []
    
    private init() {
        self.apiKey = Self.loadAPIKey()
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: config)
    }
    
    /// Public accessor for all cached RainViewer frames (past + nowcast).
    /// Returns empty array if metadata has not been fetched yet.
    var rainViewerFrames: [RainViewerFrameData] {
        stateQueue.sync { cachedRainViewerFrames }
    }

    /// The most-recent past frame, or first available frame.
    var currentRainViewerFrame: RainViewerFrameData? {
        stateQueue.sync {
            cachedRainViewerFrames.last(where: { !$0.isNowcast })
                ?? cachedRainViewerFrames.first
        }
    }

    /// Calculate tile coordinates from geographic coordinates
    /// Using Web Mercator projection (EPSG:3857)
    func tileCoordinates(latitude: Double, longitude: Double, zoom: Int) -> (x: Int, y: Int) {
        let n = pow(2.0, Double(zoom))
        
        // X coordinate
        let x = Int(floor((longitude + 180.0) / 360.0 * n))
        
        // Y coordinate
        let latRad = latitude * .pi / 180.0
        let y = Int(floor((1.0 - log(tan(latRad) + (1.0 / cos(latRad))) / .pi) / 2.0 * n))
        
        return (x, y)
    }
    
    /// Generate tile URL for a specific layer and coordinates
    func tileURL(
        layer: RadarLayer,
        precipitationSource: RadarPrecipitationSource,
        x: Int,
        y: Int,
        zoom: Int,
        framePath: String? = nil
    ) -> URL? {
        if layer == .precipitation, precipitationSource == .rainViewer {
            return rainViewerTileURL(x: x, y: y, zoom: zoom, framePath: framePath)
        }

        guard !apiKey.isEmpty else { return nil }
        let urlString = "\(openWeatherBaseURL)/\(layer.rawValue)/\(zoom)/\(x)/\(y).png?appid=\(apiKey)"
        return URL(string: urlString)
    }
    
    /// Generate tile URL from geographic coordinates
    func tileURL(layer: RadarLayer, precipitationSource: RadarPrecipitationSource, latitude: Double, longitude: Double, zoom: Int) -> URL? {
        let (x, y) = tileCoordinates(latitude: latitude, longitude: longitude, zoom: zoom)
        return tileURL(layer: layer, precipitationSource: precipitationSource, x: x, y: y, zoom: zoom)
    }

    func refreshRainViewerMetadataIfNeeded(force: Bool = false, completion: (() -> Void)? = nil) {
        let shouldRefresh: Bool = stateQueue.sync {
            if let completion {
                pendingRainViewerCompletions.append(completion)
            }

            if isRefreshingRainViewer {
                return false
            }

            if !force,
               let lastRainViewerRefresh,
               cachedRainViewerFramePath != nil,
               Date().timeIntervalSince(lastRainViewerRefresh) < rainViewerRefreshInterval {
                let completions = pendingRainViewerCompletions
                pendingRainViewerCompletions = []
                DispatchQueue.main.async {
                    completions.forEach { $0() }
                }
                return false
            }

            isRefreshingRainViewer = true
            return true
        }

        guard shouldRefresh else { return }

        session.dataTask(with: rainViewerMetadataURL) { [weak self] data, _, _ in
            guard let self else { return }

            var completions: [() -> Void] = []

            defer {
                self.stateQueue.sync {
                    self.isRefreshingRainViewer = false
                    completions = self.pendingRainViewerCompletions
                    self.pendingRainViewerCompletions = []
                }

                DispatchQueue.main.async {
                    completions.forEach { $0() }
                }
            }

            guard let data,
                  let payload = try? JSONDecoder().decode(RainViewerResponse.self, from: data) else {
                return
            }

            let selectedFramePath =
                payload.radar?.past?.last?.path ??
                payload.radar?.nowcast?.first?.path ??
                payload.radar?.past?.first?.path

            self.stateQueue.sync {
                self.cachedRainViewerHost = payload.host ?? self.rainViewerDefaultHost
                self.cachedRainViewerFramePath = selectedFramePath
                self.lastRainViewerRefresh = Date()
            }
        }.resume()
    }

    private func rainViewerTileURL(x: Int, y: Int, zoom: Int, framePath: String?) -> URL? {
        // Use provided frame, else fall back to cached latest frame
        let effectiveFramePath: String?
        if let framePath {
            effectiveFramePath = framePath
        } else {
            effectiveFramePath = stateQueue.sync { cachedRainViewerFramePath }
        }

        guard let path = effectiveFramePath else {
            refreshRainViewerMetadataIfNeeded()
            return nil
        }

        let host = (stateQueue.sync { cachedRainViewerHost } ?? rainViewerDefaultHost)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        let urlString = "\(host)\(normalizedPath)/\(rainViewerTileSize)/\(zoom)/\(x)/\(y)/\(rainViewerColorScheme)/\(rainViewerTileOptions).png"
        return URL(string: urlString)
    }

    private static func loadAPIKey() -> String {
        if let secretsURL = Bundle.main.url(forResource: "RadarSecrets", withExtension: "plist"),
           let data = try? Data(contentsOf: secretsURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let key = plist["OpenWeatherMapAPIKey"] as? String,
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key
        }

        if let key = Bundle.main.object(forInfoDictionaryKey: "OpenWeatherMapAPIKey") as? String,
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key
        }

        return ""
    }
}

private struct RainViewerResponse: Decodable {
    let host: String?
    let radar: RainViewerRadarFrames?
}

private struct RainViewerRadarFrames: Decodable {
    let past: [RainViewerFrame]?
    let nowcast: [RainViewerFrame]?
}

private struct RainViewerFrame: Decodable {
    let path: String
    let time: Int?
}

// MARK: - MapKit Tile Overlay

class WeatherTileOverlay: MKTileOverlay {
    let layer: RadarLayer
    let precipitationSource: RadarPrecipitationSource
    /// Optional RainViewer frame path for animation. When nil, uses the latest cached frame.
    var framePath: String?
    private static let transparentTileData: Data = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256))
        return renderer.pngData { context in
            UIColor.clear.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
        }
    }()
    
    init(layer: RadarLayer, precipitationSource: RadarPrecipitationSource, framePath: String? = nil) {
        self.layer = layer
        self.precipitationSource = precipitationSource
        self.framePath = framePath
        super.init(urlTemplate: nil)
        self.canReplaceMapContent = false
    }
    
    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        return RadarService.shared.tileURL(
            layer: layer,
            precipitationSource: precipitationSource,
            x: path.x,
            y: path.y,
            zoom: path.z,
            framePath: framePath
        ) ?? URL(string: "http://about:blank")! // Ensure valid URL
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, (any Error)?) -> Void) {
        guard let tileURL = RadarService.shared.tileURL(
            layer: layer,
            precipitationSource: precipitationSource,
            x: path.x,
            y: path.y,
            zoom: path.z,
            framePath: framePath
        ) else {
            if layer == .precipitation, precipitationSource == .rainViewer {
                RadarService.shared.refreshRainViewerMetadataIfNeeded(force: true) {
                    guard let refreshedURL = RadarService.shared.tileURL(
                        layer: self.layer,
                        precipitationSource: self.precipitationSource,
                        x: path.x,
                        y: path.y,
                        zoom: path.z,
                        framePath: self.framePath
                    ) else {
                        result(Self.transparentTileData, nil)
                        return
                    }

                    self.loadData(from: refreshedURL, result: result)
                }
            } else {
                result(Self.transparentTileData, nil)
            }
            return
        }

        loadData(from: tileURL, result: result)
    }

    private func loadData(from tileURL: URL, result: @escaping (Data?, (any Error)?) -> Void) {
        URLSession.shared.dataTask(with: tileURL) { data, response, _ in
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let data,
                  !data.isEmpty else {
                result(Self.transparentTileData, nil)
                return
            }

            result(data, nil)
        }.resume()
    }
}
