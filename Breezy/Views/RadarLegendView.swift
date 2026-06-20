//
//  RadarLegendView.swift
//  Breezy
//
//  Color legend for radar overlays
//

import SwiftUI

struct RadarLegendView: View {
    let layer: RadarLayer
    let precipitationSource: RadarPrecipitationSource
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        let gradient = layer.legendGradient(for: precipitationSource)

        VStack(alignment: .leading, spacing: 4) {
            LinearGradient(
                stops: gradient.map { item in
                    Gradient.Stop(
                        color: Color(hex: item.color),
                        location: normalizedPosition(for: item.value)
                    )
                },
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 92, height: 12)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
            )
            
            HStack(spacing: 0) {
                Text(gradient.first?.label ?? "")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.9))
                
                Spacer()
                
                Text(gradient.last?.label ?? "")
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.9))
            }
            .frame(width: 92)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    private func normalizedPosition(for value: Double) -> Double {
        let values = layer.legendGradient(for: precipitationSource).map { $0.value }
        guard let min = values.min(), let max = values.max(), max > min else {
            return 0.5
        }
        return (value - min) / (max - min)
    }
}
