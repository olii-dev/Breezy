//
//  MinutePrecipitationChartView.swift
//  Breezy
//
//  Minute-by-minute precipitation forecast chart
//

import SwiftUI
import Charts

struct MinutePrecipitationChartView: View {
    let minuteData: [MinuteForecast]
    let textColor: Color
    let maxMinutes: Int
    @AppStorage("Breezy.glassOpacity") private var glassOpacity: Double = 0.35
    
    @State private var selectedMinuteIndex: Int?
    @State private var isDragging = false

    init(minuteData: [MinuteForecast], textColor: Color, maxMinutes: Int = 60) {
        self.minuteData = minuteData
        self.textColor = textColor
        self.maxMinutes = max(15, maxMinutes)
    }

    private var displayedMinuteData: [MinuteForecast] {
        Array(minuteData.prefix(maxMinutes))
    }

    private var selectedMinute: (index: Int, minute: MinuteForecast)? {
        guard let selectedMinuteIndex, displayedMinuteData.indices.contains(selectedMinuteIndex) else { return nil }
        return (selectedMinuteIndex, displayedMinuteData[selectedMinuteIndex])
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerView
            
            if minuteData.isEmpty {
                emptyView
            } else {
                chartView
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(textColor.opacity(0.05))
        )
    }
    
    @ViewBuilder
    private var headerView: some View {
        HStack {
            Text("Next 60 Minutes")
                .font(.subheadline.bold())
                .foregroundColor(textColor)
            Spacer()
            Text(selectedMinuteHeader)
                .font(.caption)
                .foregroundColor(textColor.opacity(0.7))
        }
    }

    @ViewBuilder
    private var emptyView: some View {
        Text("No precipitation data available")
            .font(.caption)
            .foregroundColor(textColor.opacity(0.5))
            .frame(height: 180)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var chartView: some View {
        Chart {
            ForEach(Array(displayedMinuteData.enumerated()), id: \.offset) { index, minute in
                BarMark(
                    x: .value("Minute", index),
                    y: .value("Chance", minute.precipitationChance * 100)
                )
                .foregroundStyle(barColor(for: minute.precipitationChance))
                .cornerRadius(2)
                
                if selectedMinuteIndex == index {
                    RuleMark(x: .value("Selected", index))
                        .foregroundStyle(textColor.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: displayedMinuteData.count > 30 ? 15 : 10)) { _ in
                AxisValueLabel {
                    Text("m")
                        .font(.system(size: 10))
                        .foregroundColor(textColor.opacity(0.5))
                }
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...100)
        .frame(height: 180)
        .overlay(gestureOverlay)
    }
    
    private var gestureOverlay: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let width = geo.size.width
                            let ratio = min(max(value.location.x / width, 0), 1)
                            let count = displayedMinuteData.count
                            let newIdx = min(Int(ratio * Double(max(count - 1, 0))), count - 1)
                            if newIdx != selectedMinuteIndex {
                                HapticsManager.shared.impact(style: .light)
                            }
                            selectedMinuteIndex = newIdx
                        }
                        .onEnded { _ in
                            isDragging = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                selectedMinuteIndex = nil
                            }
                        }
                )
                .overlay(alignment: .topLeading) {
                    if let selectedMinute {
                        let x = geo.size.width * CGFloat(selectedMinute.index) / CGFloat(max(displayedMinuteData.count - 1, 1))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedMinute.index == 0 ? "Now" : "In \(selectedMinute.index) min")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(textColor)
                            Text("\(Int(selectedMinute.minute.precipitationChance * 100))% rain chance")
                                .font(.headline)
                                .foregroundColor(textColor)
                            Text(String(format: "Intensity %.1f mm/h", selectedMinute.minute.precipitationIntensity))
                                .font(.caption2)
                                .foregroundColor(textColor.opacity(0.75))
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial.opacity(glassOpacity)))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(textColor.opacity(0.12), lineWidth: 0.5))
                        .position(x: min(max(x, 72), geo.size.width - 72), y: 20)
                    }
                }
        }
    }

    private var selectedMinuteHeader: String {
        if let selectedMinute {
            return selectedMinute.index == 0 ? "Now" : "\(selectedMinute.index) min"
        }
        return "\(Int(calculateOverallChance() * 100))% chance of rain"
    }
    
    private func barColor(for chance: Double) -> Color {
        if chance < 0.1 {
            return textColor.opacity(0.15)
        } else if chance < 0.3 {
            return Color.blue.opacity(0.3)
        } else if chance < 0.6 {
            return Color.blue.opacity(0.5)
        } else {
            return Color.blue.opacity(0.8)
        }
    }
    
    private func calculateOverallChance() -> Double {
        guard !displayedMinuteData.isEmpty else { return 0 }
        let sum = displayedMinuteData.reduce(0.0) { $0 + $1.precipitationChance }
        return sum / Double(displayedMinuteData.count)
    }
}
