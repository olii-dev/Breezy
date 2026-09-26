//
//  TripMapHeader.swift
//  Breezy
//
//  Compact MapKit route preview for Trip Mode.
//

import SwiftUI
import MapKit

struct TripMapHeader: View {
    let route: TripRouteOption?
    let theme: WeatherTheme
    let glassOpacity: Double

    var body: some View {
        Group {
            if let route, !route.coordinates.isEmpty {
                TripRouteMapView(coordinates: route.coordinates.map(\.coordinate))
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.radiusL))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                            .stroke(theme.textColor.opacity(0.15), lineWidth: 0.5)
                    )
                    .overlay(alignment: .bottomLeading) {
                        HStack(spacing: 10) {
                            Label(route.travelTimeFormatted, systemImage: "car.fill")
                            Text(String(format: "%.0f km", route.distanceKilometers))
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.textColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial.opacity(glassOpacity + 0.15), in: Capsule())
                        .padding(10)
                    }
            } else {
                RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                    .fill(.ultraThinMaterial.opacity(glassOpacity))
                    .frame(height: 120)
                    .overlay {
                        ProgressView()
                            .tint(theme.textColor)
                    }
            }
        }
    }
}

private struct TripRouteMapView: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.isZoomEnabled = false
        map.isScrollEnabled = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.delegate = context.coordinator
        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)
        guard coordinates.count >= 2 else { return }

        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        mapView.addOverlay(polyline)

        let start = MKPointAnnotation()
        start.coordinate = coordinates[0]
        start.title = "Start"
        let end = MKPointAnnotation()
        end.coordinate = coordinates[coordinates.count - 1]
        end.title = "End"
        mapView.addAnnotations([start, end])

        let rect = polyline.boundingMapRect
        mapView.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 28, left: 28, bottom: 40, right: 28), animated: false)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemBlue
                renderer.lineWidth = 4
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
