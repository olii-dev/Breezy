//
//  RadarWidget.swift
//  BreezyWidget
//
//  Home Screen radar card: a static composite of the latest RainViewer frame
//  over a dark base map. The first image-based widget in the extension —
//  compositing mirrors the watch app's proven tile engine (512px-capable
//  fetch, RainViewer error-tile fingerprint, ancestor-pyramid fallback).
//

import WidgetKit
import SwiftUI
import MapKit
import CoreLocation
import CryptoKit

// MARK: - Entry

struct RadarWidgetEntry: TimelineEntry {
    let date: Date
    let image: UIImage?
    let frameTime: Date?
    let city: String?
}

// MARK: - Timeline Provider

struct RadarWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> RadarWidgetEntry {
        RadarWidgetEntry(date: Date(), image: nil, frameTime: nil, city: "Cupertino")
    }

    func getSnapshot(in context: Context, completion: @escaping (RadarWidgetEntry) -> Void) {
        Task {
            completion(await makeEntry(context: context))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RadarWidgetEntry>) -> Void) {
        Task {
            let entry = await makeEntry(context: context)
            // Radar frames advance every ~10 min; widget budget gets a say.
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
        }
    }

    private func makeEntry(context: Context) async -> RadarWidgetEntry {
        guard let coords = await resolveLocation() else {
            return RadarWidgetEntry(date: Date(), image: nil, frameTime: nil, city: nil)
        }

        let city = (try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: coords.lat, longitude: coords.lon)))?.first?.locality
            ?? WeatherDataStore.load()?.city

        guard let composite = try? await RadarWidgetComposer.shared.latestComposite(
            latitude: coords.lat,
            longitude: coords.lon
        ) else {
            return RadarWidgetEntry(date: Date(), image: nil, frameTime: nil, city: city)
        }

        return RadarWidgetEntry(date: Date(), image: composite.image, frameTime: composite.frameTime, city: city)
    }

    /// Location chain copied from the main Provider: GPS when following,
    /// else the app's last cached coordinates.
    private func resolveLocation() async -> (lat: Double, lon: Double)? {
        let defaults = UserDefaults(suiteName: "group.com.breezy.weather")
        let shouldFollowGPS: Bool = {
            if defaults?.object(forKey: "Breezy.shouldFollowGPS") == nil { return true }
            return defaults?.bool(forKey: "Breezy.shouldFollowGPS") ?? true
        }()

        if shouldFollowGPS {
            if let loc = try? await WidgetLocationManager.shared.requestLocation() {
                defaults?.set(loc.coordinate.latitude, forKey: "LastLatitude")
                defaults?.set(loc.coordinate.longitude, forKey: "LastLongitude")
                return (loc.coordinate.latitude, loc.coordinate.longitude)
            }
        }

        if let cached = WeatherDataStore.load(),
           let lat = cached.latitude, let lon = cached.longitude {
            return (lat, lon)
        }
        if let lat = defaults?.object(forKey: "LastLatitude") as? Double,
           let lon = defaults?.object(forKey: "LastLongitude") as? Double, lat != 0, lon != 0 {
            return (lat, lon)
        }
        return nil
    }
}

// MARK: - Static Radar Composer

final class RadarWidgetComposer {
    static let shared = RadarWidgetComposer()

    private let session: URLSession
    /// City-level: the deepest zoom RainViewer serves real radar for.
    private let zoom = 7
    private let gridExtent = 1
    private var cachedFrame: (path: String, time: Date)?
    private var frameFetchedAt: Date?

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
    }

    func latestComposite(latitude: Double, longitude: Double) async throws -> (image: UIImage, frameTime: Date) {
        let frame = try await latestFrame()
        return try await composite(latitude: latitude, longitude: longitude, framePath: frame.path, frameTime: frame.time)
    }

    private func latestFrame() async throws -> (path: String, time: Date) {
        if let cachedFrame, let frameFetchedAt,
           Date().timeIntervalSince(frameFetchedAt) < 8 * 60 {
            return cachedFrame
        }

        guard let url = URL(string: "https://api.rainviewer.com/public/weather-maps.json") else {
            throw NSError(domain: "RadarWidget", code: 0)
        }
        let (data, _) = try await session.data(from: url)
        struct Meta: Decodable {
            struct RadarBlock: Decodable {
                struct Frame: Decodable {
                    let path: String
                    let time: TimeInterval
                }
                let past: [Frame]
                let nowcast: [Frame]?
            }
            let radar: RadarBlock
        }
        let meta = try JSONDecoder().decode(Meta.self, from: data)
        // Latest OBSERVED frame — nowcast stays off the Home Screen.
        guard let latest = meta.radar.past.last else {
            throw NSError(domain: "RadarWidget", code: 1)
        }
        let frame = (path: latest.path, time: Date(timeIntervalSince1970: latest.time))
        cachedFrame = frame
        frameFetchedAt = Date()
        return frame
    }

    private func composite(latitude: Double, longitude: Double, framePath: String, frameTime: Date) async throws -> (image: UIImage, frameTime: Date) {
        let size = 768
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let n = pow(2.0, Double(zoom))
        let span = 360.0 / n * Double(gridExtent * 2 + 1) * cos(latitude * .pi / 180)

        // Dark base map, with a plain dark fill if MapKit can't deliver.
        var base: UIImage?
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)
        )
        options.size = CGSize(width: size, height: size)
        options.scale = 1.0
        options.mapType = .standard
        options.showsBuildings = false
        let snapshotter = MKMapSnapshotter(options: options)
        base = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MKMapSnapshotter.Snapshot, Error>) in
            snapshotter.start { snapshot, error in
                if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "RadarWidget", code: 2))
                }
            }
        }.image

        guard let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "RadarWidget", code: 3)
        }

        let fullRect = CGRect(x: 0, y: 0, width: size, height: size)
        if let baseCG = base?.cgImage {
            ctx.draw(baseCG, in: fullRect)
        } else {
            ctx.setFillColor(red: 0.08, green: 0.1, blue: 0.14, alpha: 1)
            ctx.fill(fullRect)
        }

        // Radar tiles over the base.
        let (centerX, centerY) = Self.tileCoordinates(latitude: latitude, longitude: longitude, zoom: zoom)
        let tileSize = size / (gridExtent * 2 + 1)

        try await withThrowingTaskGroup(of: (Int, Int, UIImage?).self) { group in
            for dx in -gridExtent...gridExtent {
                for dy in -gridExtent...gridExtent {
                    let x = centerX + dx
                    let y = centerY + dy
                    group.addTask { [weak self] in
                        guard let self else { return (dx, dy, nil) }
                        let tile = await self.fetchTileWithFallback(z: self.zoom, x: x, y: y, framePath: framePath)
                        return (dx, dy, tile)
                    }
                }
            }

            for try await (dx, dy, tile) in group {
                guard let tile, let cgTile = tile.cgImage else { continue }
                let destX = (dx + gridExtent) * tileSize
                // Tile Y grows southward; context Y grows northward.
                let destY = (gridExtent - dy) * tileSize
                ctx.draw(cgTile, in: CGRect(x: destX, y: destY, width: tileSize, height: tileSize))
            }
        }

        // Flatten the radar at a readable translucency.
        guard let overlayCtx = CGContext(
            data: nil,
            width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let composed = ctx.makeImage() else {
            throw NSError(domain: "RadarWidget", code: 4)
        }
        _ = overlayCtx
        overlayCtx.setAlpha(1)
        overlayCtx.draw(composed, in: fullRect)

        guard let final = overlayCtx.makeImage() else {
            throw NSError(domain: "RadarWidget", code: 5)
        }
        return (UIImage(cgImage: final), frameTime)
    }

    private func fetchTileWithFallback(z: Int, x: Int, y: Int, framePath: String, depth: Int = 0) async -> UIImage? {
        let n = Int(pow(2.0, Double(max(z, 0))))
        let wrappedX = ((x % n) + n) % n
        let path = framePath.hasPrefix("/") ? framePath : "/\(framePath)"
        guard let url = URL(string: "https://tilecache.rainviewer.com\(path)/256/\(z)/\(wrappedX)/\(y)/6/1_1.png") else {
            return nil
        }
        if let tile = await fetchTile(url: url) {
            return tile
        }
        guard z > 0, depth < 6 else { return nil }
        return await fetchTileWithFallback(z: z - 1, x: x >> 1, y: y >> 1, framePath: framePath, depth: depth + 1)
    }

    private func fetchTile(url: URL) async -> UIImage? {
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              !data.isEmpty, !Self.isTileServerError(data) else {
            return nil
        }
        return UIImage(data: data)
    }

    /// md5 fingerprints of RainViewer's fixed "zoom level not supported"
    /// error tiles (256px and 512px variants — byte-stable across frames).
    private static let tileServerErrorMD5s: Set<String> = [
        "2cc6649e1f2ec818def1b4d8f911958d",
        "6227f878c487498df3f64f8ac0636a57"
    ]

    static func isTileServerError(_ data: Data) -> Bool {
        guard data.count < 8192 else { return false }
        let digest = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return tileServerErrorMD5s.contains(digest)
    }

    private static func tileCoordinates(latitude: Double, longitude: Double, zoom: Int) -> (x: Int, y: Int) {
        let n = pow(2.0, Double(zoom))
        let x = Int((longitude + 180.0) / 360.0 * n)
        let latRad = latitude * .pi / 180.0
        let y = Int((1.0 - asinh(tan(latRad)) / .pi) / 2.0 * n)
        return (x, y)
    }
}

// MARK: - Widget Views

struct RadarWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RadarWidgetEntry

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = entry.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color(red: 0.08, green: 0.1, blue: 0.14)
                    VStack(spacing: 4) {
                        Image(systemName: "map")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.5))
                        Text("Radar unavailable")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }

            // Translucent info chip.
            HStack(spacing: 6) {
                Image(systemName: "location.fill")
                    .font(.caption2)
                if let city = entry.city {
                    Text(city)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
                if let frameTime = entry.frameTime {
                    Text("·")
                    Text(frameTime, style: .time)
                        .font(.caption2)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.black.opacity(0.45), in: Capsule())
            .padding(family == .systemSmall ? 6 : 8)
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "breezy://radar"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Radar for \(entry.city ?? "your location")\(entry.frameTime != nil ? ", frame as of \(entry.frameTime!.formatted(date: .omitted, time: .shortened))" : "")")
        .accessibilityHint(entry.image == nil ? "Radar unavailable" : "Opens the full radar")
        .clipShape(RoundedRectangle(cornerRadius: family == .systemLarge ? 22 : 16, style: .continuous))
    }
}

struct RadarWidget: Widget {
    static let kind = "BreezyRadarWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: RadarWidgetProvider()) { entry in
            RadarWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Radar")
        .description("The latest rain radar for your location.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
