//
//  SunPathView.swift
//  Breezy
//
//  Visual arc showing the sun's position relative to sunrise and sunset.
//

import SwiftUI

//
//  SunPathView.swift
//  Breezy
//
//  Visual arc showing the sun's position relative to sunrise and sunset.
//

import SwiftUI

struct SunPathView: View {
    let sunrise: Date
    let sunset: Date
    let currentTime: Date? // Optional: If nil, hides current progress
    let textColor: Color
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let arcHeight = h * 0.5 // Height of the arc
            let horizonY = h * 0.8  // Y position of the horizon
            
            ZStack {
                // 1. Horizon Line
                Path { path in
                    path.move(to: CGPoint(x: 0, y: horizonY))
                    path.addLine(to: CGPoint(x: w, y: horizonY))
                }
                .stroke(textColor.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                
                // 2. Sun Arc Fill (Gradient under curve)
                Path { path in
                    path.move(to: CGPoint(x: 20, y: horizonY))
                    path.addQuadCurve(
                        to: CGPoint(x: w - 20, y: horizonY),
                        control: CGPoint(x: w / 2, y: horizonY - arcHeight * 2)
                    )
                }
                .stroke(
                    LinearGradient(
                        colors: [.orange.opacity(0.6), .yellow, .orange.opacity(0.6)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .background(
                    // Faint fill under the curve
                    Path { path in
                        path.move(to: CGPoint(x: 20, y: horizonY))
                        path.addQuadCurve(
                            to: CGPoint(x: w - 20, y: horizonY),
                            control: CGPoint(x: w / 2, y: horizonY - arcHeight * 2)
                        )
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [.orange.opacity(0.15), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                )
                
                // 3. Sun Indicator
                if let pos = sunProgress {
                    let point = pointOnQuadCurve(
                        t: pos,
                        p0: CGPoint(x: 20, y: horizonY),
                        c: CGPoint(x: w / 2, y: horizonY - arcHeight * 2), // Must match control point above
                        p1: CGPoint(x: w - 20, y: horizonY)
                    )
                    
                    // Sun Glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.orange.opacity(0.6), .clear],
                                center: .center,
                                startRadius: 2,
                                endRadius: 20
                            )
                        )
                        .frame(width: 40, height: 40)
                        .position(point)
                        .blur(radius: 2)
                    
                    // Sun Core
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .position(point)
                        .shadow(color: .orange, radius: 4)
                        .overlay(
                            Circle()
                                .stroke(Color.orange, lineWidth: 2)
                                .frame(width: 10, height: 10)
                                .position(point)
                        )
                }
                
                // Countdown Label / Center Status
                VStack {
                    if let countdown = timeUntilEvent {
                        Text(countdown.title)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(textColor.opacity(0.6))
                            .textCase(.uppercase)
                        Text(countdown.time)
                            .font(.title3.bold()) // 4. Larger font for emphasis
                            .foregroundColor(textColor)
                    } else {
                        // If no current time (future day), maybe show just "Daylight" again or empty?
                        // Let's show "Daylight Duration" here too, prominently?
                        // Or leave blank to keep it clean.
                        // Actually, the user asked for sunrise/sunset times, which are at the bottom.
                        // The arc is nice.
                    }
                }
                .offset(y: 15) // Position INSIDE the ring (below the arc, above horizon)
                
                // Labels
                VStack {
                    Spacer()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sunrise")
                                .font(.caption2.weight(.medium))
                                .foregroundColor(textColor.opacity(0.6))
                            Text(formatTime(sunrise))
                                .font(.subheadline.bold())
                                .foregroundColor(textColor)
                        }
                        Spacer()
                        
                        // Daylight Duration (Center)
                        VStack(spacing: 0) {
                             Text("Daylight")
                                .font(.caption2)
                                .foregroundColor(textColor.opacity(0.5))
                                .textCase(.uppercase)
                             Text(daylightDuration)
                                .font(.caption.bold())
                                .foregroundColor(textColor.opacity(0.8))
                        }
                        .offset(y: 4)
                        
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Sunset")
                                .font(.caption2.weight(.medium))
                                .foregroundColor(textColor.opacity(0.6))
                            Text(formatTime(sunset))
                                .font(.subheadline.bold())
                                .foregroundColor(textColor)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(height: 130) // Reduced height since countdown is now inside
    }
    
    // Progress 0.0 (Sunrise) -> 1.0 (Sunset)
    var sunProgress: CGFloat? {
        guard let currentTime = currentTime else { return nil }
        
        let total = sunset.timeIntervalSince(sunrise)
        let current = currentTime.timeIntervalSince(sunrise)
        
        if total <= 0 { return nil }
        
        // Clamp 0...1 if daytime, otherwise nil or show at ends?
        if current < 0 { return 0.0 } // Pre-sunrise (show at start)
        if current > total { return 1.0 } // Post-sunset (show at end)
        
        return CGFloat(current / total)
    }
    
    var daylightDuration: String {
        let diff = sunset.timeIntervalSince(sunrise)
        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
    
    // Quadratic Bezier Point Calculation
    // B(t) = (1-t)^2 * P0 + 2(1-t)t * C + t^2 * P1
    func pointOnQuadCurve(t: CGFloat, p0: CGPoint, c: CGPoint, p1: CGPoint) -> CGPoint {
        let x = pow(1 - t, 2) * p0.x + 2 * (1 - t) * t * c.x + pow(t, 2) * p1.x
        let y = pow(1 - t, 2) * p0.y + 2 * (1 - t) * t * c.y + pow(t, 2) * p1.y
        return CGPoint(x: x, y: y)
    }
    
    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
    
    var timeUntilEvent: (title: String, time: String)? {
        guard let now = currentTime else { return nil }
        
        if now < sunrise {
            let diff = sunrise.timeIntervalSince(now)
            return ("Sunrise in", formatDuration(diff))
        } else if now < sunset {
            let diff = sunset.timeIntervalSince(now)
            return ("Sunset in", formatDuration(diff))
        } else {
            return ("Sun Set", "")
        }
    }
    
    func formatDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}
