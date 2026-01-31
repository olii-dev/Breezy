//
//  RadarCardView.swift
//  Breezy
//
//  Weather radar overlay viewer
//

import SwiftUI
import MapKit

struct RadarCardView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedLayer: RadarLayer = .precipitation
    @State private var region: MKCoordinateRegion
    @State private var showFullScreen = false
    @State private var showLayerMenu = false
    @State private var isLoading = true
    
    init(viewModel: WeatherViewModel) {
        self.viewModel = viewModel
        
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
        VStack(alignment: .leading, spacing: 12) {
            // Header with layer menu button
            HStack {
                Label("Weather Radar", systemImage: "tornado")
                    .font(.caption.weight(.bold))
                    .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.6))
                
                Spacer()
                
                Button {
                    showLayerMenu = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selectedLayer.icon)
                        Text(selectedLayer.displayName)
                        Image(systemName: "chevron.down")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                    )
                }
            }
            
            // Map with radar overlay
            ZStack {
                RadarMapView(
                    region: $region,
                    layer: selectedLayer,
                    isLoading: $isLoading,
                    coordinate: CLLocationCoordinate2D(
                    latitude: viewModel.currentLocation?.latitude ?? 0,
                    longitude: viewModel.currentLocation?.longitude ?? 0
                ),
                isDark: viewModel.currentTheme(colorScheme: colorScheme).isDark,
                mapStyle: viewModel.mapStyle
            )
                .frame(height: 300)
                .cornerRadius(DesignSystem.radiusM)
                
                // Loading indicator (Non-blocking)
                if isLoading {
                    VStack {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                            Text("Updating radar...")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                        )
                        .shadow(radius: 4)
                        .padding(.top, 12)
                        
                        Spacer()
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                // Legend (top right) - compact version
                if !isLoading {
                    VStack {
                        HStack {
                            Spacer()
                            
                            // Map Style Button
                            Menu {
                                Picker("Map Style", selection: $viewModel.mapStyle) {
                                    ForEach(WeatherViewModel.RadarMapStyle.allCases) { style in
                                        Text(style.rawValue).tag(style)
                                    }
                                }
                            } label: {
                                Image(systemName: "map.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Circle().fill(Color.black.opacity(0.4)))
                            }
                            .padding(.trailing, 8)
                            
                            RadarLegendView(layer: selectedLayer)
                                .padding(.trailing, 8)
                        }
                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }
        }
        .softGlassCard(padding: DesignSystem.spacingM, cornerRadius: DesignSystem.radiusM)
        .onTapGesture {
            showFullScreen = true
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            FullScreenRadarView(viewModel: viewModel)
        }
        .sheet(isPresented: $showLayerMenu) {
            RadarLayerMenuView(selectedLayer: $selectedLayer)
        }
        .onChange(of: selectedLayer) { oldValue, newValue in
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
    @Binding var isLoading: Bool
    let coordinate: CLLocationCoordinate2D
    var isDark: Bool
    var mapStyle: WeatherViewModel.RadarMapStyle
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.showsUserLocation = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.showsCompass = false
        mapView.showsScale = false
        
        // Configure Map Style
        configureMapStyle(mapView)
        
        mapView.overrideUserInterfaceStyle = isDark ? .dark : .light
        
        // Add radar overlay
        let overlay = OpenWeatherTileOverlay(layer: layer)
        overlay.canReplaceMapContent = false
        mapView.addOverlay(overlay, level: .aboveLabels)
        
        // Add location marker
        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        mapView.addAnnotation(annotation)
        
        // Set loading to false after a short delay (tiles start loading)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation { isLoading = false }
        }
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
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
        
        // Update overlay if layer changed
        let currentTileOverlay = mapView.overlays.first(where: { $0 is OpenWeatherTileOverlay }) as? OpenWeatherTileOverlay
        
        if currentTileOverlay?.layer != layer {
            // Remove existing radar overlays
            let radarOverlays = mapView.overlays.filter { $0 is OpenWeatherTileOverlay }
            if !radarOverlays.isEmpty {
                mapView.removeOverlays(radarOverlays)
            }
            
            // Add new overlay
            let overlay = OpenWeatherTileOverlay(layer: layer)
            mapView.addOverlay(overlay, level: .aboveLabels)
            
            // Hide loading after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation { isLoading = false }
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
        case .hybrid:
            mapView.preferredConfiguration = MKHybridMapConfiguration()
            mapView.mapType = .hybrid
        case .satellite:
            mapView.preferredConfiguration = MKImageryMapConfiguration()
            mapView.mapType = .satellite
        case .muted:
            let config = MKStandardMapConfiguration()
            config.emphasisStyle = .muted
            mapView.preferredConfiguration = config
            mapView.mapType = .mutedStandard
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: RadarMapView
        
        init(_ parent: RadarMapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tileOverlay = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tileOverlay)
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            DispatchQueue.main.async {
                self.parent.region = mapView.region
            }
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
