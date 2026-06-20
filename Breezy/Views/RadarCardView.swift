//
//  RadarCardView.swift
//  Breezy
//
//  Weather radar overlay viewer
//

import SwiftUI
import MapKit

struct RadarCardView: View {
    @ObservedObject     var viewModel: WeatherViewModel
    var locationHelper: LocationHelper? = nil
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedLayer: RadarLayer = .precipitation
    @State private var region: MKCoordinateRegion
    @State private var showFullScreen = false
    @State private var showLayerMenu = false
    @State private var isLoading = true

    private var precipitationSource: RadarPrecipitationSource {
        viewModel.radarPrecipitationSource
    }
    
    init(viewModel: WeatherViewModel, locationHelper: LocationHelper? = nil) {
        self.viewModel = viewModel
        self.locationHelper = locationHelper
        
        // Initialize map region centered on current location
        let initialCoordinate = CLLocationCoordinate2D(
            latitude: viewModel.currentLocation?.latitude ?? 0,
            longitude: viewModel.currentLocation?.longitude ?? 0
        )
        
        _region = State(initialValue: MKCoordinateRegion(
            center: initialCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 5.0, longitudeDelta: 5.0)
        ))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Standard Header
            HStack {
                Label("Weather Radar", systemImage: "tornado")
                    .font(.caption.weight(.bold))
                    .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.6))
                
                Spacer()
                
                Button {
                    HapticsManager.shared.impact(style: .light)
                    showLayerMenu = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: selectedLayer.icon)
                        Text(selectedLayer.displayName)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            // Map Content
            ZStack(alignment: .bottomTrailing) {
                RadarMapView(
                    region: $region,
                    layer: selectedLayer,
                    precipitationSource: precipitationSource,
                    isLoading: $isLoading,
                    coordinate: CLLocationCoordinate2D(
                        latitude: viewModel.currentLocation?.latitude ?? 0,
                        longitude: viewModel.currentLocation?.longitude ?? 0
                    ),
                    isDark: viewModel.currentTheme(colorScheme: colorScheme).isDark,
                    mapStyle: viewModel.mapStyle
                )
                .frame(height: 200)
                .cornerRadius(DesignSystem.radiusM)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                
                // Map Style Mini-Button
                Button {
                    HapticsManager.shared.impact(style: .light)
                    // Cycle through styles
                    let styles = WeatherViewModel.RadarMapStyle.allCases
                    if let index = styles.firstIndex(of: viewModel.mapStyle) {
                        viewModel.mapStyle = styles[(index + 1) % styles.count]
                    }
                } label: {
                    Image(systemName: "map.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                        .padding(8)
                        .background(.ultraThinMaterial.opacity(viewModel.glassOpacity))
                        .clipShape(Circle())
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
                
                if isLoading {
                    ProgressView()
                        .tint(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                        .padding(20)
                }
            }
        }
        .softGlassCard(padding: 0)
        .shadow(color: Color.black.opacity(0.15), radius: 18, x: 0, y: 10)
        .onTapGesture {
            HapticsManager.shared.impact(style: .light)
            showFullScreen = true
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            FullScreenRadarView(viewModel: viewModel, locationHelper: locationHelper)
        }
        .sheet(isPresented: $showLayerMenu) {
            RadarLayerMenuView(selectedLayer: $selectedLayer, precipitationSource: precipitationSource)
        }
        .onChange(of: selectedLayer) { oldValue, newValue in
            HapticsManager.shared.impact(style: .light)
            withAnimation { isLoading = true }
        }
        .onChange(of: precipitationSource) { _, _ in
            withAnimation { isLoading = true }
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
    }
}

// MARK: - MapKit Wrapper

struct RadarMapView: UIViewRepresentable {
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
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.showsUserLocation = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.showsCompass = true
        mapView.showsScale = false
        
        // Configure Map Style
        configureMapStyle(mapView)
        
        mapView.overrideUserInterfaceStyle = isDark ? .dark : .light

        if layer == .precipitation, precipitationSource == .rainViewer {
            RadarService.shared.refreshRainViewerMetadataIfNeeded()
        }
        
        // Add radar overlay
        let overlay = WeatherTileOverlay(layer: layer, precipitationSource: precipitationSource)
        overlay.canReplaceMapContent = false
        mapView.addOverlay(overlay, level: .aboveLabels)
        context.coordinator.beginLoading()
        
        // Add location marker (searched city)
        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        annotation.title = "CityLocation"
        mapView.addAnnotation(annotation)
        
        // Add GPS dot if viewing a different city
        if showGPSDot, let gps = userGPSLocation {
            let gpsAnnotation = MKPointAnnotation()
            gpsAnnotation.coordinate = gps
            gpsAnnotation.title = "GPSLocation"
            mapView.addAnnotation(gpsAnnotation)
        }
        
        // Loading will be controlled by delegate methods
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self

        // Update style if needed
        if mapView.overrideUserInterfaceStyle != (isDark ? .dark : .light) {
            mapView.overrideUserInterfaceStyle = isDark ? .dark : .light
        }
        
        configureMapStyle(mapView)
        
        // Update region if changed
        if mapView.region.center.latitude != region.center.latitude ||
           mapView.region.center.longitude != region.center.longitude {
            mapView.setRegion(region, animated: true)
        }
        
        // Update overlay if layer, source, or animation frame changed
        let currentTileOverlay = mapView.overlays.first(where: { $0 is WeatherTileOverlay }) as? WeatherTileOverlay

        let needsSwap: Bool = {
            guard let current = currentTileOverlay else { return true }
            if current.layer != layer || current.precipitationSource != precipitationSource { return true }
            // Frame path mismatch only matters when animating RainViewer precipitation
            if layer == .precipitation && precipitationSource == .rainViewer {
                return current.framePath != framePath
            }
            return false
        }()

        if needsSwap {
            // Remove existing radar overlays
            let radarOverlays = mapView.overlays.filter { $0 is WeatherTileOverlay }
            if !radarOverlays.isEmpty {
                mapView.removeOverlays(radarOverlays)
            }

            // Add new overlay
            if layer == .precipitation, precipitationSource == .rainViewer {
                RadarService.shared.refreshRainViewerMetadataIfNeeded()
            }
            let overlay = WeatherTileOverlay(layer: layer, precipitationSource: precipitationSource, framePath: framePath)
            mapView.addOverlay(overlay, level: .aboveLabels)
            // Only show loading spinner on layer/source changes, not frame animation steps
            if currentTileOverlay?.layer != layer || currentTileOverlay?.precipitationSource != precipitationSource {
                context.coordinator.beginLoading()
            }
        }
        
        // Update annotation position
        if let annotation = mapView.annotations.first as? MKPointAnnotation,
           annotation.coordinate.latitude != coordinate.latitude ||
           annotation.coordinate.longitude != coordinate.longitude {
            annotation.coordinate = coordinate
        }
    }
    
    private func configureMapStyle(_ mapView: MKMapView) {
        switch mapStyle {
        case .standard:
            mapView.preferredConfiguration = MKStandardMapConfiguration()
            mapView.mapType = .standard
        case .satellite:
            mapView.preferredConfiguration = MKImageryMapConfiguration()
            mapView.mapType = .satellite
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    static func dismantleUIView(_ mapView: MKMapView, coordinator: Coordinator) {
        coordinator.stopLoading(reason: false)
        mapView.delegate = nil
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
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
            let identifier = "LocationPulse"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            
            if annotationView == nil {
                annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = false
                
                // Create pulsing view
                let pulsingView = PulsingLocationView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
                annotationView?.frame = pulsingView.frame
                annotationView?.addSubview(pulsingView)
            } else {
                annotationView?.annotation = annotation
            }
            
            return annotationView
        }
    }
}

// Custom pulsing view using CoreAnimation
class PulsingLocationView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        backgroundColor = .clear
        
        // Center dot
        let dotPath = UIBezierPath(ovalIn: CGRect(x: 12, y: 12, width: 16, height: 16))
        let dotLayer = CAShapeLayer()
        dotLayer.path = dotPath.cgPath
        dotLayer.fillColor = UIColor.systemBlue.cgColor
        dotLayer.strokeColor = UIColor.white.cgColor
        dotLayer.lineWidth = 4
        dotLayer.shadowColor = UIColor.black.cgColor
        dotLayer.shadowOpacity = 0.2
        dotLayer.shadowRadius = 4
        dotLayer.shadowOffset = CGSize(width: 0, height: 2)
        layer.addSublayer(dotLayer)
        
        // Pulse animation
        let pulseLayer = CAShapeLayer()
        pulseLayer.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 40, height: 40)).cgPath
        pulseLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.3).cgColor
        pulseLayer.position = CGPoint(x: 20, y: 20)
        pulseLayer.bounds = CGRect(x: 0, y: 0, width: 40, height: 40)
        
        let initialScale = CATransform3DMakeScale(0.4, 0.4, 1)
        pulseLayer.transform = initialScale
        
        layer.insertSublayer(pulseLayer, below: dotLayer)
        
        let scaleAnimation = CAMediaTimingFunction(name: .easeOut)
        
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = 0.4
        animation.toValue = 1.0
        animation.duration = 2.0
        animation.timingFunction = scaleAnimation
        animation.repeatCount = .infinity
        
        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = 0.5
        opacityAnimation.toValue = 0.0
        opacityAnimation.duration = 2.0
        opacityAnimation.timingFunction = scaleAnimation
        opacityAnimation.repeatCount = .infinity
        
        pulseLayer.add(animation, forKey: "pulse")
        pulseLayer.add(opacityAnimation, forKey: "opacity")
    }
}
