//
//  RadarLegendView.swift
//  Breezy
//
//  Color legend for radar overlays
//

import SwiftUI

struct RadarLegendView: View {
    let layer: RadarLayer
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Gradient bar - thinner and more compact
            LinearGradient(
                stops: layer.legendGradient.map { item in
                    Gradient.Stop(
                        color: Color(hex: item.color),
                        location: normalizedPosition(for: item.value)
                    )
                },
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 80, height: 12)
            .cornerRadius(3)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
            )
            
            // Value labels (compact, just min and max)
            HStack(spacing: 0) {
                Text(layer.legendGradient.first?.label ?? "")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.9))
                
                Spacer()
                
                Text(layer.legendGradient.last?.label ?? "")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.9))
            }
            .frame(width: 80)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.7))
        )
    }
    
    private func normalizedPosition(for value: Double) -> Double {
        let values = layer.legendGradient.map { $0.value }
        guard let min = values.min(), let max = values.max(), max > min else {
            return 0.5
        }
        return (value - min) / (max - min)
    }
}
