//
//  RadarLayerMenuView.swift
//  Breezy
//
//  Floating menu for radar layer selection
//

import SwiftUI
import CoreLocation

struct RadarLayerMenuView: View {
    @Binding var selectedLayer: RadarLayer
    let precipitationSource: RadarPrecipitationSource
    @Binding var showLightning: Bool
    var strikeOrigin: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Radar Layer")
                    .font(.title3.bold())
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .padding()
            .padding(.top, 8)
            
            Divider()
            
            // Layer options
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(RadarLayer.allCases) { layer in
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                selectedLayer = layer
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 16) {
                                // Icon in circle
                                ZStack {
                                    Circle()
                                        .fill(selectedLayer == layer ? Color.blue : Color.gray.opacity(0.2))
                                        .frame(width: 50, height: 50)
                                    
                                    Image(systemName: layer.icon)
                                        .font(.title3)
                                        .foregroundColor(selectedLayer == layer ? .white : .primary)
                                }
                                
                                // Name and description
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(layer.displayName)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    Text(layerDescription(for: layer))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                // Color preview gradient
                                HStack(spacing: 1) {
                                    ForEach(0..<5, id: \.self) { index in
                                        let colors = layer.legendGradient(for: precipitationSource)
                                        let colorIndex = min((index * colors.count) / 5, colors.count - 1)
                                        Rectangle()
                                            .fill(Color(hex: colors[colorIndex].color))
                                            .frame(width: 8, height: 40)
                                    }
                                }
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                                
                                // Checkmark
                                if selectedLayer == layer {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(selectedLayer == layer ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(selectedLayer == layer ? Color.blue : Color.clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // Live lightning overlay (independent of the base layer).
                    Toggle(isOn: $showLightning) {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(showLightning ? Color.yellow : Color.gray.opacity(0.2))
                                    .frame(width: 50, height: 50)

                                Image(systemName: "bolt.fill")
                                    .font(.title3)
                                    .foregroundColor(showLightning ? .white : .primary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Lightning Strikes")
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                Text("Live strikes from the Blitzortung community network")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(showLightning ? Color.yellow.opacity(0.1) : Color.gray.opacity(0.05))
                        )
                    }
                    .tint(.yellow)

                    #if DEBUG
                    Button {
                        LightningService.shared.injectSampleStrikes(around: strikeOrigin)
                    } label: {
                        Label("Add test strikes (debug)", systemImage: "ladybug")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.gray.opacity(0.05))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    #endif
                }
                .padding()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    private func layerDescription(for layer: RadarLayer) -> String {
        switch layer {
        case .precipitation:
            return precipitationSource == .rainViewer ? "Live radar precipitation via RainViewer" : "Rain and snow intensity"
        case .wind: return "Wind speed patterns"
        case .clouds: return "Cloud cover density"
        case .temperature: return "Global temperature map"
        case .pressure: return "Atmospheric pressure"
        }
    }
}
