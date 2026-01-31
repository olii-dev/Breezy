//
//  RadarService.swift
//  Breezy
//
//  OpenWeatherMap tile service for radar overlays
//

import Foundation
import CoreLocation
import MapKit

enum RadarLayer: String, CaseIterable, Identifiable {
    case precipitation = "precipitation_new"
    case clouds = "clouds_new"
    case temperature = "temp_new"
    case pressure = "pressure_new"
    case wind = "wind_new"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .precipitation: return "Precipitation"
        case .clouds: return "Clouds"
        case .temperature: return "Temperature"
        case .pressure: return "Pressure"
        case .wind: return "Wind Speed"
        }
    }
    
    var icon: String {
        switch self {
        case .precipitation: return "cloud.rain.fill"
        case .clouds: return "cloud.fill"
        case .temperature: return "thermometer"
        case .pressure: return "gauge"
        case .wind: return "wind"
        }
    }
    
    /// Accurate OpenWeatherMap color scales with gradients
    var legendGradient: [(value: Double, color: String, label: String)] {
        switch self {
        case .precipitation:
            // mm/hr - Official OWM scale
            return [
                (0, "#00000000", "0"),
                (0.1, "#C89696", "0.1"),
                (0.5, "#7878BE", "0.5"),
                (1, "#6E6ECD", "1"),
                (10, "#5050E1", "10"),
                (50, "#1414FF", "50+ mm/h")
            ]
        case .clouds:
            // % coverage - Official OWM scale
            return [
                (0, "#00000000", "0%"),
                (10, "#FDFDFF", "10%"),
                (30, "#FAFAFF", "30%"),
                (50, "#F7F7FF", "50%"),
                (70, "#F4F4FF", "70%"),
                (100, "#F0F0FF", "100%")
            ]
        case .temperature:
            // °C - Official OWM scale
            return [
                (-65, "#821692", "< -40°C"),
                (-30, "#8257DB", "-30°C"),
                (-20, "#208CEC", "-20°C"),
                (-10, "#20C4E8", "-10°C"),
                (0, "#23DDDD", "0°C"),
                (10, "#C2FF28", "10°C"),
                (20, "#FFF028", "20°C"),
                (25, "#FFC228", "25°C"),
                (30, "#FC8014", "30°C+")
            ]
        case .pressure:
            // Pa - Official OWM scale
            return [
                (940, "#0073FF", "< 980"),
                (960, "#00AAFF", "980"),
                (980, "#4BD0D6", "1000"),
                (1000, "#8DE7C7", "1013"),
                (1010, "#B0F720", "1020"),
                (1020, "#F0B800", "1030"),
                (1040, "#FB5515", "1040"),
                (1060, "#F3363B", "> 1050 hPa")
            ]
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
        }
    }
}

class RadarService {
    static let shared = RadarService()
    private let apiKey = "dc636a9dc2be15804fd8d1076bdcdf3a"
    private let baseURL = "https://tile.openweathermap.org/map"
    
    private init() {}
    
    /// Time range for radar animation (in minutes from current time)
    static let pastTimeRange: Int = 180  // 3 hours back
    static let futureTimeRange: Int = 120 // 2 hours forward
    
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
    func tileURL(layer: RadarLayer, x: Int, y: Int, zoom: Int) -> URL? {
        let urlString = "\(baseURL)/\(layer.rawValue)/\(zoom)/\(x)/\(y).png?appid=\(apiKey)"
        return URL(string: urlString)
    }
    
    /// Generate tile URL from geographic coordinates
    func tileURL(layer: RadarLayer, latitude: Double, longitude: Double, zoom: Int) -> URL? {
        let (x, y) = tileCoordinates(latitude: latitude, longitude: longitude, zoom: zoom)
        return tileURL(layer: layer, x: x, y: y, zoom: zoom)
    }
}

// MARK: - MapKit Tile Overlay

class OpenWeatherTileOverlay: MKTileOverlay {
    let layer: RadarLayer
    
    init(layer: RadarLayer) {
        self.layer = layer
        super.init(urlTemplate: nil)
        self.canReplaceMapContent = false
    }
    
    override func url(forTilePath path: MKTileOverlayPath) -> URL {
        return RadarService.shared.tileURL(
            layer: layer,
            x: path.x,
            y: path.y,
            zoom: path.z
        ) ?? URL(string: "http://about:blank")! // Ensure valid URL
    }
}
