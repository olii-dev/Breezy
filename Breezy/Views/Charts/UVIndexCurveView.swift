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
                ForEach(hourlyForecast) { hour in
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
                                VStack(spacing: 2) {
                                    Text("\(hour.uvIndex ?? 0)")
                                        .font(.system(.title3, design: .rounded).bold())
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                    
                                    Text(formatHour(hour.hourValue))
                                        .font(.caption2.weight(.medium))
                                        .foregroundColor(.secondary)
                                }
                                .padding(6)
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)
                                .shadow(radius: 4)
                            }
                    } else if selectedHour == nil, hour.hourValue == Calendar.current.component(.hour, from: Date()) {
                         // Default "Now" indicator when not scrubbing
                        PointMark(
                            x: .value("Time", hour.hourValue),
                            y: .value("UV", hour.uvIndex ?? 0)
                        )
                        .symbolSize(0) // handled by .symbol above, just used for annotation anchor
                        .annotation(position: .top) {
                            Text("\(currentUV)")
                                .font(.caption.bold())
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
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
                                    let origin = geometry[proxy.plotFrame!].origin
                                    let location = CGPoint(
                                        x: value.location.x - origin.x,
                                        y: value.location.y - origin.y
                                    )
                                    if let hour: Int = proxy.value(atX: location.x) {
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
                AxisMarks(values: .stride(by: 6)) { value in
                    if let hour = value.as(Int.self) {
                        AxisValueLabel {
                            Text(formatHour(hour))
                                .font(.caption2)
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
