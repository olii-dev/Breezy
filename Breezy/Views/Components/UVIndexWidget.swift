//
//  UVIndexWidget.swift
//  Breezy
//
//  Widget displaying UV Index
//

import SwiftUI

struct UVIndexWidget: View {
    let weather: WeatherInfo
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "sun.max.fill")
                    .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.7))
                Text("UV Index")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.8))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            if let uvIndex = weather.metrics?.uvIndex {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(uvIndex)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                    
                    Text(weather.metrics?.uvIndexCategory ?? category(for: uvIndex))
                        .font(.headline)
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                    
                    // Simple Progress Bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 6)
                            
                            Capsule()
                                .fill(color(for: uvIndex))
                                .frame(width: min(CGFloat(uvIndex) / 11.0 * geo.size.width, geo.size.width), height: 6)
                        }
                    }
                    .frame(height: 6)
                    .padding(.top, 8)
                    
                    Text(description(for: uvIndex))
                        .font(.caption)
                        .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.7))
                        .padding(.top, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            } else {
                Text("N/A")
                    .padding()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
    }
    
    func category(for uv: Int) -> String {
        switch uv {
        case 0...2: return "Low"
        case 3...5: return "Moderate"
        case 6...7: return "High"
        case 8...10: return "Very High"
        default: return "Extreme"
        }
    }
    
    func color(for uv: Int) -> Color {
        switch uv {
        case 0...2: return .green
        case 3...5: return .yellow
        case 6...7: return .orange
        case 8...10: return .red
        default: return .purple
        }
    }
    
    func description(for uv: Int) -> String {
        switch uv {
        case 0...2: return "No protection needed."
        case 3...5: return "Seek shade during midday hours."
        case 6...7: return "Protection required. Reduces time in sun."
        case 8...10: return "Extra protection needed. Be careful."
        default: return "Take all precautions. Skin can burn in minutes."
        }
    }
}
