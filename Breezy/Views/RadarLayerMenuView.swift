//
//  RadarLayerMenuView.swift
//  Breezy
//
//  Floating menu for radar layer selection
//

import SwiftUI

struct RadarLayerMenuView: View {
    @Binding var selectedLayer: RadarLayer
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
                                        let colors = layer.legendGradient
                                        let colorIndex = min((index * colors.count) / 5, colors.count - 1)
                                        Rectangle()
                                            .fill(Color(hex: colors[colorIndex].color) ?? .clear)
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
                }
                .padding()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    private func layerDescription(for layer: RadarLayer) -> String {
        switch layer {
        case .precipitation: return "Rain and snow intensity"
        case .clouds: return "Cloud coverage percentage"
        case .temperature: return "Temperature distribution"
        case .pressure: return "Atmospheric pressure"
        case .wind: return "Wind speed patterns"
        }
    }
}
