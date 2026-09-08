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
    var rangeHours: Int = 24
    var showPeak: Bool = true
    @AppStorage("Breezy.glassOpacity") private var glassOpacity: Double = 0.35
    @AppStorage("Breezy.typography") private var typographyRaw: String = WeatherFont.system.rawValue

    private var typographyDesign: Font.Design {
        WeatherFont(rawValue: typographyRaw)?.design ?? .default
    }

    private var annotationColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var chartHours: [HourlyForecast] {
        // Drop yesterday's hours (allHourlyData now includes past_days=1) so the
        // curve reflects the upcoming day.
        let now = Date()
        let upcoming = hourlyForecast
            .filter { ($0.uvIndex ?? 0) >= 0 }
            .filter { hour in
                guard let date = hour.sourceDate else { return true }
                return date >= now.addingTimeInterval(-1800)
            }
            .sorted { lhs, rhs in
                switch (lhs.sourceDate, rhs.sourceDate) {
                case let (left?, right?):
                    return left < right
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                case (nil, nil):
                    return lhs.hourValue < rhs.hourValue
                }
            }
        let limit = max(1, rangeHours)
        return Array(upcoming.prefix(limit))
    }

    private var peakIndex: Int? {
        guard let peak = chartHours.enumerated().max(by: { ($0.element.uvIndex ?? 0) < ($1.element.uvIndex ?? 0) }) else {
            return nil
        }
        guard (peak.element.uvIndex ?? 0) > 0 else { return nil }
        return peak.offset
    }

    private var nowIndex: Int? {
        let currentHour = Calendar.current.component(.hour, from: Date())
        if let byDate = chartHours.firstIndex(where: {
            guard let date = $0.sourceDate else { return false }
            return abs(date.timeIntervalSinceNow) < 1800
        }) {
            return byDate
        }
        return chartHours.firstIndex(where: { $0.hourValue == currentHour })
    }

    private var xAxisValues: [Int] {
        guard !chartHours.isEmpty else { return [0] }
        let strideStep = rangeHours <= 12 ? 3 : 6
        return chartHours.indices.filter { index in
            index == 0 || index == chartHours.count - 1 || index % strideStep == 0
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
    
    @State private var selectedIndex: Int?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            chartView
        }
    }
    
    var chartView: some View {
        let xDomainMax = max(chartHours.count - 1, 1)
        return VStack(spacing: 8) {
            Chart {
                ForEach(Array(chartHours.enumerated()), id: \.element.id) { index, hour in
                    AreaMark(
                        x: .value("Index", index),
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
                        .opacity(0.6)
                    )
                    
                    LineMark(
                        x: .value("Index", index),
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
                        if let selected = selectedIndex, selected == index {
                            Circle()
                                .fill(annotationColor)
                                .frame(width: 8, height: 8)
                                .shadow(radius: 2)
                        } else if selectedIndex == nil, nowIndex == index {
                            Circle()
                                .fill(.white)
                                .frame(width: 10, height: 10)
                                .shadow(radius: 2)
                        }
                    }
                    
                    if let selected = selectedIndex, selected == index {
                        RuleMark(x: .value("Index", selected))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .foregroundStyle(annotationColor.opacity(0.5))
                            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                VStack(spacing: 4) {
                                    Text("\(hour.uvIndex ?? 0)")
                                        .font(.system(.title3, design: typographyDesign).bold())
                                        .foregroundColor(annotationColor)
                                
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
                    }
                }
                
                if showPeak, selectedIndex == nil, let peakIndex, chartHours.indices.contains(peakIndex) {
                    let peakHour = chartHours[peakIndex]
                    let peakValue = peakHour.uvIndex ?? 0
                    RuleMark(x: .value("Peak", peakIndex))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(color(for: peakValue).opacity(0.8))
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            VStack(spacing: 4) {
                                Text("Peak UV")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(annotationColor.opacity(0.78))
                                Text("\(peakValue)")
                                    .font(.system(.headline, design: typographyDesign).weight(.bold))
                                    .foregroundColor(annotationColor)
                                Text(formatHour(peakHour.hourValue))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(10)
                            .background(.ultraThinMaterial.opacity(glassOpacity))
                            .cornerRadius(12)
                            .shadow(radius: 6)
                        }
                }
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
                                    if let index: Int = proxy.value(atX: location.x) {
                                        let clamped = min(max(index, 0), chartHours.count - 1)
                                        if clamped != self.selectedIndex {
                                            HapticsManager.shared.impact(style: .light)
                                        }
                                        self.selectedIndex = clamped
                                    }
                                }
                                .onEnded { _ in
                                    self.selectedIndex = nil
                                }
                        )
                }
            }
            .chartXAxis {
                AxisMarks(values: xAxisValues) { value in
                    AxisValueLabel {
                        if let index = value.as(Int.self), chartHours.indices.contains(index) {
                            Text(formatAxisHour(chartHours[index].hourValue))
                                .font(.system(size: 11, weight: .medium))
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
            .chartXScale(domain: 0...xDomainMax)
            .frame(height: 180)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    private func formatHour(_ hour: Int) -> String {
        DateFormatterHelper.hourLabel(hour)
    }

    private func formatAxisHour(_ hour: Int) -> String {
        guard !DateFormatterHelper.uses24HourClock else {
            return "\(hour):00"
        }
        let displayHour = (hour == 0 || hour == 12 || hour == 24) ? 12 : hour % 12
        return "\(displayHour)\(hour < 12 || hour == 24 ? "AM" : "PM")"
    }
}
