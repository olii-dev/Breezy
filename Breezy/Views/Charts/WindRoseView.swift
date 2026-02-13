//
//  WindRoseView.swift
//  Breezy
//
//  Visualizes wind direction and speed.
//

import SwiftUI

struct WindRoseView: View {
    let speed: Double // km/h
    let direction: String // "N", "NW", etc.
    let degree: Double // 0-360
    let color: Color
    
    var body: some View {
        ZStack {
            // Compass Background
            ForEach(0..<8) { i in
                Rectangle()
                    .fill(color.opacity(0.1))
                    .frame(width: 1, height: 120)
                    .rotationEffect(.degrees(Double(i) * 45))
            }
            
            // Cardinal Directions
            ForEach(Cardinal.allCases, id: \.self) { card in
                Text(card.rawValue)
                    .font(.caption2.bold())
                    .foregroundColor(color.opacity(0.6))
                    .offset(x: 0, y: -70)
                    .rotationEffect(.degrees(card.rotation))
            }
            
            // Concentric Circles (Speed rings)
            ForEach(1...3, id: \.self) { i in
                Circle()
                    .stroke(color.opacity(0.05), lineWidth: 1)
                    .frame(width: CGFloat(i) * 40, height: CGFloat(i) * 40)
            }
            
            // The Indicator Arrow
            VStack(spacing: 0) {
                // Arrowhead
                Image(systemName: "location.north.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundColor(color)
                    .shadow(color: color.opacity(0.4), radius: 4)
                
                // Shaft
                Rectangle()
                    .fill(LinearGradient(colors: [color, color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 2, height: 40)
            }
            .offset(y: -20)
            .rotationEffect(.degrees(degree))
            
            // Center Metrics
            VStack(spacing: 0) {
                Text("\(Int(speed))")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                Text("km/h")
                    .font(.caption2)
                    .foregroundColor(color.opacity(0.7))
            }
        }
        .frame(height: 160)
    }
    
    enum Cardinal: String, CaseIterable {
        case N, E, S, W
        
        var rotation: Double {
            switch self {
            case .N: return 0
            case .E: return 90
            case .S: return 180
            case .W: return 270
            }
        }
    }
}
