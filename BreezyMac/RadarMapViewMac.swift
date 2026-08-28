//
//  RadarMapViewMac.swift
//  BreezyMac
//
//  AppKit-backed radar map mirroring the iOS RadarMapView (RadarCardView.swift)
//  memberwise surface: tile overlays, city/GPS annotations, lightning strike
//  pins with age fade. All MapKit types used already exist on macOS.
//

#if os(macOS)
import SwiftUI
import MapKit
import AppKit

struct RadarMapView: NSViewRepresentable {
    @Binding var region: MKCoordinateRegion
    let layer: RadarLayer
    let precipitationSource: RadarPrecipitationSource
    @Binding var isLoading: Bool
    let coordinate: CLLocationCoordinate2D
    var userGPSLocation: CLLocationCoordinate2D?
    var showGPSDot: Bool = false
    var isDark: Bool
    var mapStyle: WeatherViewModel.RadarMapStyle
    /// Optional RainViewer frame path for animation. Pass nil for latest frame.
    var framePath: String?
    /// Live lightning strikes to pin on the map (Blitzortung feed).
    var strikes: [LightningStrike] = []

    /// Never render more than this many bolts.
    private static let maxRenderedStrikes = 150

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.showsUserLocation = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.showsCompass = true
        mapView.showsScale = false

        configureMapStyle(mapView)
        mapView.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)

        if layer == .precipitation, precipitationSource == .rainViewer {
            RadarService.shared.refreshRainViewerMetadataIfNeeded()
        }

        let overlay = WeatherTileOverlay(layer: layer, precipitationSource: precipitationSource)
        overlay.canReplaceMapContent = false
        mapView.addOverlay(overlay, level: .aboveLabels)
        context.coordinator.beginLoading()

        addLocationAnnotations(to: mapView)
        syncLightningAnnotations(on: mapView)
        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self

        mapView.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        configureMapStyle(mapView)

        if mapView.region.center.latitude != region.center.latitude ||
           mapView.region.center.longitude != region.center.longitude {
            mapView.setRegion(region, animated: true)
        }

        // Swap the tile overlay when layer/source/animation frame changes.
        let currentTileOverlay = mapView.overlays.first(where: { $0 is WeatherTileOverlay }) as? WeatherTileOverlay
        let needsSwap: Bool = {
            guard let current = currentTileOverlay else { return true }
            if current.layer != layer || current.precipitationSource != precipitationSource { return true }
            if layer == .precipitation && precipitationSource == .rainViewer {
                return current.framePath != framePath
            }
            return false
        }()

        if needsSwap {
            let radarOverlays = mapView.overlays.filter { $0 is WeatherTileOverlay }
            if !radarOverlays.isEmpty {
                mapView.removeOverlays(radarOverlays)
            }
            if layer == .precipitation, precipitationSource == .rainViewer {
                RadarService.shared.refreshRainViewerMetadataIfNeeded()
            }
            let overlay = WeatherTileOverlay(layer: layer, precipitationSource: precipitationSource, framePath: framePath)
            mapView.addOverlay(overlay, level: .aboveLabels)
            if currentTileOverlay?.layer != layer || currentTileOverlay?.precipitationSource != precipitationSource {
                context.coordinator.beginLoading()
            }
        }

        updateCityAnnotation(on: mapView)
        syncLightningAnnotations(on: mapView)
    }

    static func dismantleNSView(_ mapView: MKMapView, coordinator: Coordinator) {
        coordinator.stopLoading(reason: false)
        mapView.delegate = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Annotations

    private func addLocationAnnotations(to mapView: MKMapView) {
        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        annotation.title = "CityLocation"
        mapView.addAnnotation(annotation)

        if showGPSDot, let gps = userGPSLocation {
            let gpsAnnotation = MKPointAnnotation()
            gpsAnnotation.coordinate = gps
            gpsAnnotation.title = "GPSLocation"
            mapView.addAnnotation(gpsAnnotation)
        }
    }

    private func updateCityAnnotation(on mapView: MKMapView) {
        if let annotation = mapView.annotations.first(where: { ($0 as? MKPointAnnotation)?.title == "CityLocation" }) as? MKPointAnnotation,
           annotation.coordinate.latitude != coordinate.latitude ||
           annotation.coordinate.longitude != coordinate.longitude {
            annotation.coordinate = coordinate
        }
    }

    /// Add/remove/re-age bolt pins so the map always mirrors the strike buffer.
    private func syncLightningAnnotations(on mapView: MKMapView) {
        let desired = Array(strikes.suffix(Self.maxRenderedStrikes))
        let desiredIDs = Set(desired.map(\.id))

        let existing = mapView.annotations.compactMap { $0 as? LightningStrikeAnnotation }
        let stale = existing.filter { !desiredIDs.contains($0.strikeID) }
        if !stale.isEmpty {
            mapView.removeAnnotations(stale)
        }

        let existingIDs = Set(existing.map(\.strikeID))
        let fresh = desired.filter { !existingIDs.contains($0.id) }
        if !fresh.isEmpty {
            mapView.addAnnotations(fresh.map { LightningStrikeAnnotation(strike: $0) })
        }

        let now = Date()
        for case let annotation as LightningStrikeAnnotation in mapView.annotations {
            (mapView.view(for: annotation) as? LightningAnnotationView)?.updateFade(for: annotation.date, now: now)
        }
    }

    private func configureMapStyle(_ mapView: MKMapView) {
        switch mapStyle {
        case .standard:
            mapView.preferredConfiguration = MKStandardMapConfiguration()
        case .satellite:
            mapView.preferredConfiguration = MKImageryMapConfiguration()
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: RadarMapView
        private var loadingTimer: Timer?

        init(_ parent: RadarMapView) {
            self.parent = parent
        }

        func beginLoading() {
            DispatchQueue.main.async {
                self.parent.isLoading = true
                self.startLoadingTimerIfNeeded()
            }
        }

        private func startLoadingTimerIfNeeded() {
            guard loadingTimer == nil else { return }
            loadingTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.parent.isLoading = false
                    self?.loadingTimer = nil
                }
            }
        }

        func stopLoading(reason fullyRendered: Bool) {
            loadingTimer?.invalidate()
            loadingTimer = nil

            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tileOverlay)
                renderer.alpha = 0.8
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            DispatchQueue.main.async {
                self.parent.region = mapView.region
            }
        }

        func mapViewWillStartRenderingMap(_ mapView: MKMapView) {
            startLoadingTimerIfNeeded()
        }

        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            if fullyRendered {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    self.stopLoading(reason: true)
                }
            }
        }

        func mapViewDidFinishLoadingMap(_ mapView: MKMapView) {
            stopLoading(reason: true)
        }

        func mapViewDidFailLoadingMap(_ mapView: MKMapView, withError error: Error) {
            stopLoading(reason: false)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let strikeAnnotation = annotation as? LightningStrikeAnnotation {
                let identifier = "LightningBolt"
                var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? LightningAnnotationView
                if view == nil {
                    view = LightningAnnotationView(annotation: strikeAnnotation, reuseIdentifier: identifier)
                } else {
                    view?.annotation = strikeAnnotation
                }
                view?.updateFade(for: strikeAnnotation.date, now: Date())
                return view
            }

            let identifier = "LocationPulse"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)

            if annotationView == nil {
                annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = false

                let pulsingView = PulsingLocationView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
                annotationView?.frame = pulsingView.frame
                annotationView?.addSubview(pulsingView)
            } else {
                annotationView?.annotation = annotation
            }

            return annotationView
        }
    }
}

// MARK: - Lightning annotations

/// MKPointAnnotation carrying the strike identity for diffing.
final class LightningStrikeAnnotation: MKPointAnnotation {
    let strikeID: String
    let date: Date

    init(strike: LightningStrike) {
        self.strikeID = strike.id
        self.date = strike.date
        super.init()
        self.coordinate = strike.coordinate
    }
}

/// Yellow bolt badge that fades out over the strike retention window.
final class LightningAnnotationView: MKAnnotationView {
    private static let retentionInterval: TimeInterval = 30 * 60

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false

        let bolt = NSImageView()
        if let symbol = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) {
            bolt.image = symbol.withSymbolConfiguration(.init(pointSize: 11, weight: .bold))
        }
        bolt.contentTintColor = .white

        let badge = NSView(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.systemYellow.cgColor
        badge.layer?.cornerRadius = 11
        badge.layer?.borderColor = NSColor.black.withAlphaComponent(0.35).cgColor
        badge.layer?.borderWidth = 1
        badge.layer?.shadowColor = NSColor.black.cgColor
        badge.layer?.shadowOpacity = 0.35
        badge.layer?.shadowRadius = 2
        badge.layer?.shadowOffset = NSSize(width: 0, height: -1)
        badge.addSubview(bolt)
        bolt.frame = badge.bounds

        frame = badge.frame
        addSubview(badge)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Linear fade across the retention window, floored so old strikes stay
    /// faintly visible until pruned.
    func updateFade(for date: Date, now: Date) {
        let age = now.timeIntervalSince(date)
        let fraction = CGFloat(max(0, 1 - age / Self.retentionInterval))
        alphaValue = 0.35 + 0.65 * fraction
    }
}

// Custom pulsing view using CoreAnimation (mirrors the iOS PulsingLocationView).
final class PulsingLocationView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer = CALayer()
        layer?.frame = NSRect(x: 0, y: 0, width: 40, height: 40).cgRect

        let dotRadius: CGFloat = 8
        let dot = CAShapeLayer()
        dot.path = CGPath(ellipseIn: NSRect(x: 20 - dotRadius, y: 20 - dotRadius, width: dotRadius * 2, height: dotRadius * 2), transform: nil)
        dot.fillColor = NSColor.controlAccentColor.cgColor
        dot.strokeColor = NSColor.white.cgColor
        dot.lineWidth = 4
        dot.shadowColor = NSColor.black.cgColor
        dot.shadowOpacity = 0.2
        dot.shadowRadius = 4
        dot.shadowOffset = CGSize(width: 0, height: -2)
        layer?.addSublayer(dot)

        let pulse = CAShapeLayer()
        pulse.path = CGPath(ellipseIn: NSRect(x: 0, y: 0, width: 40, height: 40), transform: nil)
        pulse.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
        pulse.position = CGPoint(x: 20, y: 20)
        pulse.bounds = NSRect(x: 0, y: 0, width: 40, height: 40)
        pulse.setAffineTransform(CGAffineTransform(scaleX: 0.4, y: 0.4))

        layer?.insertSublayer(pulse, below: dot)

        let timing = CAMediaTimingFunction(name: .easeOut)

        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 0.4
        scaleAnimation.toValue = 1.0
        scaleAnimation.duration = 2.0
        scaleAnimation.timingFunction = timing
        scaleAnimation.repeatCount = .infinity

        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = 0.5
        opacityAnimation.toValue = 0.0
        opacityAnimation.duration = 2.0
        opacityAnimation.timingFunction = timing
        opacityAnimation.repeatCount = .infinity

        pulse.add(scaleAnimation, forKey: "pulse")
        pulse.add(opacityAnimation, forKey: "opacity")
    }
}

private extension NSRect {
    var cgRect: CGRect {
        CGRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }
}
#endif
