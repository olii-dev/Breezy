//
//  UVIndexCurveView.swift
//  Breezy
//
//  A chart visualizing the UV Index throughout the day.
//  Uses a bell-curve style representation of UV intensity.
//

import SwiftUI
import Charts

struct UVIndexCurveView: View {
    let hourlyForecast: [HourlyForecast]
    let currentUV: Int
    let colorScheme: ColorScheme
    @AppStorage("Breezy.glassOpacity") private var glassOpacity: Double = 0.35
    @AppStorage("Breezy.typography") private var typographyRaw: String = WeatherFont.system.rawValue

    private var typographyDesign: Font.Design {
        WeatherFont(rawValue: typographyRaw)?.design ?? .default
    }

    private var chartHours: [HourlyForecast] {
        hourlyForecast
            .filter { ($0.uvIndex ?? 0) >= 0 }
            .filter { (0...23).contains($0.hourValue) }
            .sorted { lhs, rhs in
                if lhs.hourValue == rhs.hourValue {
                    return lhs.time < rhs.time
                }
                return lhs.hourValue < rhs.hourValue
            }
    }
    
    // UV Categories for color coding
    func color(for uv: Int) -> Color {
        switch uv {
        case 0...2: return .green
        case 3...5: return .yellow
        case 6...7: return .orange
        case 8...10: return .red
        default: return .purple
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            chartView
        }
    }
    
    @State private var selectedHour: Int?
    
    var chartView: some View {
        VStack(spacing: 8) {
            Chart {
                ForEach(chartHours) { hour in
                    // Area under curve with vertical gradient
                    AreaMark(
                        x: .value("Time", hour.hourValue),
                        y: .value("UV", hour.uvIndex ?? 0)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            stops: [
                                .init(color: .green, location: 0.0),    // UV 0
                                .init(color: .yellow, location: 0.25),  // UV 3
                                .init(color: .orange, location: 0.5),   // UV 6
                                .init(color: .red, location: 0.75),     // UV 9
                                .init(color: .purple, location: 1.0)    // UV 12+
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                        .opacity(0.6)
                    )
                    
                    // Line on top
                    LineMark(
                        x: .value("Time", hour.hourValue),
                        y: .value("UV", hour.uvIndex ?? 0)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            stops: [
                                .init(color: .green, location: 0.0),
                                .init(color: .yellow, location: 0.25),
                                .init(color: .orange, location: 0.5),
                                .init(color: .red, location: 0.75),
                                .init(color: .purple, location: 1.0)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .lineStyle(StrokeStyle(lineWidth: 3))
                    .symbol {
                        // Show symbol for selected hour or current time (if nothing selected)
                        if let selected = selectedHour, selected == hour.hourValue {
                            Circle()
                                .fill(colorScheme == .dark ? .white : .black)
                                .frame(width: 8, height: 8)
                                .shadow(radius: 2)
                        } else if selectedHour == nil, hour.hourValue == Calendar.current.component(.hour, from: Date()) {
                            Circle()
                                .fill(.white)
                                .frame(width: 10, height: 10)
                                .shadow(radius: 2)
                        }
                    }
                    
                    // RuleMark for scrubbing interaction
                    if let selected = selectedHour, selected == hour.hourValue {
                        RuleMark(x: .value("Time", selected))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .foregroundStyle(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                VStack(spacing: 4) {
                                    Text("\(hour.uvIndex ?? 0)")
                                        .font(.system(.title3, design: typographyDesign).bold())
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                    Text(formatHour(hour.hourValue))
                                        .font(.caption2.weight(.medium))
                                        .foregroundColor(.secondary)
                                }
                                .padding(12)
                                .frame(minWidth: 140)
                                .background(.ultraThinMaterial.opacity(glassOpacity))
                                .cornerRadius(12)
                                .shadow(radius: 6)
                            }
                    } else if selectedHour == nil, hour.hourValue == Calendar.current.component(.hour, from: Date()) {
                         // Default "Now" indicator when not scrubbing
                        PointMark(
                            x: .value("Time", hour.hourValue),
                            y: .value("UV", hour.uvIndex ?? 0)
                        )
                        .symbolSize(0)
                    }
                }
                
                // Safety Threshold Line (Removed)
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    guard !chartHours.isEmpty else { return }
                                    guard let plotFrame = proxy.plotFrame else { return }
                                    let frame = geometry[plotFrame]
                                    guard frame.width > 0 else { return }
                                    let location = CGPoint(
                                        x: value.location.x - frame.origin.x,
                                        y: value.location.y - frame.origin.y
                                    )
                                    guard location.x >= 0, location.x <= frame.width else { return }
                                    if let hour: Int = proxy.value(atX: location.x) {
                                        if hour != self.selectedHour {
                                            HapticsManager.shared.impact(style: .light)
                                        }
                                        self.selectedHour = hour
                                    }
                                }
                                .onEnded { _ in
                                    self.selectedHour = nil
                                }
                        )
                }
            }
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    AxisValueLabel {
                        if let hour = value.as(Int.self), hour >= 0 && hour < 24 {
                            let hourLabel = hour == 0 ? "12 AM" : hour == 6 ? "6 AM" : hour == 12 ? "12 PM" : hour == 18 ? "6 PM" : hour == 23 ? "11 PM" : ""
                            if !hourLabel.isEmpty {
                                Text(hourLabel)
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic) { value in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartYScale(domain: 0...12)
            .chartXScale(domain: 0...24)
            .frame(height: 180)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    private func formatHour(_ hour: Int) -> String {
        let displayHour = (hour == 0 || hour == 12 || hour == 24) ? 12 : hour % 12
        let suffix = hour < 12 || hour == 24 ? "AM" : "PM"
        return "\(displayHour)\(suffix)"
    }
}
