//
//  WeatherMetricsView.swift
//  Breezy
//
//  Weather metrics display view
//

import SwiftUI
import Foundation

struct WeatherMetricsView: View {
    let metrics: WeatherMetrics
    
    var body: some View {
        VStack(spacing: 16) {
            // UV Index
            if let uvIndex = metrics.uvIndex {
                MetricCard(
                    icon: "sun.max.fill",
                    title: "UV Index",
                    value: "\(uvIndex)",
                    subtitle: metrics.uvIndexCategory ?? "",
                    color: uvColor(for: uvIndex),
                    recommendation: UVIndexHelper.recommendation(for: uvIndex)
                )
            }
            
            // Air Quality
            if let airQuality = metrics.airQuality, let aqi = airQuality.aqi {
                MetricCard(
                    icon: "aqi.medium",
                    title: "Air Quality",
                    value: "\(aqi)",
                    subtitle: airQuality.category ?? "",
                    color: aqiColor(for: aqi),
                    recommendation: AirQualityHelper.recommendation(for: aqi)
                )
            }
            
            // Two-column grid for other metrics
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                // Pressure
                if let pressure = metrics.pressure {
                    SmallMetricCard(icon: "barometer", title: "Pressure", value: pressure)
                }
                
                // Visibility
                if let visibility = metrics.visibility {
                    SmallMetricCard(icon: "eye.fill", title: "Visibility", value: visibility)
                }
                
                // Dew Point
                if let dewPoint = metrics.dewPoint {
                    SmallMetricCard(icon: "drop.fill", title: "Dew Point", value: dewPoint)
                }
                
                // Humidity
                if let humidity = metrics.humidity {
                    SmallMetricCard(icon: "humidity.fill", title: "Humidity", value: "\(humidity)%")
                }
            }
            
            // Wind Direction with Compass
            if let windDirection = metrics.windDirection,
               let windCardinal = metrics.windDirectionCardinal {
                WindDirectionCard(
                    direction: windDirection,
                    cardinal: windCardinal,
                    windSpeed: metrics.windSpeed
                )
            }
        }
        .padding(.horizontal)
    }
    
    private func uvColor(for index: Int) -> Color {
        switch index {
        case 0...2:
            return .green
        case 3...5:
            return .yellow
        case 6...7:
            return .orange
        case 8...10:
            return .red
        default:
            return .purple
        }
    }
    
    private func aqiColor(for aqi: Int) -> Color {
        switch aqi {
        case 0...50:
            return .green
        case 51...100:
            return .yellow
        case 101...150:
            return .orange
        case 151...200:
            return .red
        case 201...300:
            return .purple
        default:
            return .red
        }
    }
}

struct MetricCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    let recommendation: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
            
            Text(recommendation)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Color.white.opacity(0.15))
        .cornerRadius(16)
    }
}

struct SmallMetricCard: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.white.opacity(0.8))
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            Text(value)
                .font(.headline)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white.opacity(0.15))
        .cornerRadius(12)
    }
}

struct WindDirectionCard: View {
    let direction: Double
    let cardinal: String
    let windSpeed: String?
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "wind")
                    .foregroundColor(.white.opacity(0.8))
                Text("Wind")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(cardinal)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    if let speed = windSpeed {
                        Text(speed)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    .frame(width: 120, height: 120)
                
                // Compass directions
                ForEach(0..<8) { index in
                    let angle = Double(index) * 45.0
                    let radian = angle * .pi / 180.0
                    let x = cos(radian) * 50
                    let y = sin(radian) * 50
                    
                    Text(directionLabel(for: index))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                        .offset(x: x, y: y)
                }
                
                // Wind direction arrow
                ArrowShape(angle: direction)
                    .fill(Color.white)
                    .frame(width: 60, height: 60)
            }
        }
        .padding()
        .background(Color.white.opacity(0.15))
        .cornerRadius(16)
    }
    
    private func directionLabel(for index: Int) -> String {
        let labels = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return labels[index]
    }
}

struct ArrowShape: Shape {
    let angle: Double
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let length: CGFloat = 30
        let width: CGFloat = 4
        
        // Convert angle to radians (0 = North, clockwise)
        let radian = (angle - 90) * .pi / 180.0
        
        // Arrow pointing in wind direction
        let tip = CGPoint(
            x: center.x + CGFloat(cos(radian)) * length,
            y: center.y + CGFloat(sin(radian)) * length
        )
        
        let left = CGPoint(
            x: center.x + CGFloat(cos(radian + .pi * 0.8)) * width,
            y: center.y + CGFloat(sin(radian + .pi * 0.8)) * width
        )
        
        let right = CGPoint(
            x: center.x + CGFloat(cos(radian - .pi * 0.8)) * width,
            y: center.y + CGFloat(sin(radian - .pi * 0.8)) * width
        )
        
        path.move(to: tip)
        path.addLine(to: left)
        path.addLine(to: center)
        path.addLine(to: right)
        path.closeSubpath()
        
        return path
    }
}

