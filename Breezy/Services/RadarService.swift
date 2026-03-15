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
