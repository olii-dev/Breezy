//
//  WidgetPreviewView.swift
//  Breezy
//
//  Created for Custom Widget Builder
//

import SwiftUI

struct WidgetPreviewView: View {
    let config: CustomWidgetConfiguration
    @AppStorage("Breezy.glassOpacity") private var glassOpacity: Double = 0.35
    // We use mock data for the preview to avoid complex dependency injection
    // In the real widget, this would use real WeatherEntry data
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 0) {
                     // Date Header Removed as per user request
                     Spacer().frame(height: 12)
 
                    // Content based on Layout Style
                    switch config.layoutStyle {
                    case .standard:
                        standardLayout
                    case .split:
                        splitLayout
                    case .list:
                        listLayout
                    case .minimal:
                        minimalLayout
                    }
                }
            }
            .frame(width: width(for: config.widgetSize), height: height(for: config.widgetSize))
            .background(backgroundView) // Apply as background modifier
            .clipShape(ContainerRelativeShape()) // Mimic widget shape
            .overlay(
                 RoundedRectangle(cornerRadius: 22, style: .continuous) // Approximate radius
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: config.showBorder ? 1 : 0)
            )
            .shadow(radius: 10)
        }
    }
    
    // MARK: - Layouts
    
    var standardLayout: some View {
        VStack {
            // Top Row
            HStack {
                metricView(for: .topLeft)
                Spacer()
                // Top Center (Medium/Large only effectively, but logic is generic)
                metricView(for: .topCenter)
                Spacer()
                metricView(for: .topRight)
            }
            
            Spacer()
            
            // Middle Row
            HStack {
                metricView(for: .middleLeft)
                Spacer()
                metricView(for: .center)
                Spacer()
                metricView(for: .middleRight)
            }
            
            Spacer()
            
            // Bottom Row
            HStack {
                metricView(for: .bottomLeft)
                Spacer()
                // Bottom Center
                metricView(for: .bottomCenter)
                Spacer()
                metricView(for: .bottomRight)
            }
        }
        .padding()
    }
    
    var splitLayout: some View {
        HStack(spacing: 20) {
            // Left Column
            VStack {
                metricView(for: .topLeft)
                Spacer()
                metricView(for: .middleLeft)
                Spacer()
                metricView(for: .bottomLeft)
            }
            
            Divider().background(Color.white.opacity(0.3))
            
            // Right Column
            VStack {
                metricView(for: .topRight)
                Spacer()
                metricView(for: .middleRight)
                Spacer()
                metricView(for: .bottomRight)
            }
        }
        .padding()
    }
    
    var listLayout: some View {
        VStack(spacing: 12) {
            // Simple logic: Render enabled metrics in a specific order
            // Top Left -> Top Right -> etc.
            
            HStack { metricView(for: .topLeft); Spacer() }
            HStack { metricView(for: .topCenter); Spacer() }
            HStack { metricView(for: .topRight); Spacer() }
            HStack { metricView(for: .middleLeft); Spacer() }
            HStack { metricView(for: .middleRight); Spacer() }
            HStack { metricView(for: .bottomLeft); Spacer() }
            HStack { metricView(for: .bottomCenter); Spacer() }
            HStack { metricView(for: .bottomRight); Spacer() }
        }
        .padding()
    }
    
    var minimalLayout: some View {
        ZStack {
            metricView(for: .center)
        }
        .padding()
    }
    
    // MARK: - Dimensions
    
    func width(for size: WidgetSize) -> CGFloat {
        switch size {
        case .small: return 160
        case .medium: return 330
        case .large: return 330
        }
    }
    
    func height(for size: WidgetSize) -> CGFloat {
        switch size {
        case .small, .medium: return 160
        case .large: return 345
        }
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        switch config.backgroundStyle {
        case .solid:
            if let custom = config.customColors.first {
                custom.color
            } else {
                Color.blue
            }
        case .gradient:
            if config.customColors.count >= 2 {
                LinearGradient(
                    colors: config.customColors.map { $0.color },
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                // Default Blue Gradient
                LinearGradient(
                    colors: [.blue, .cyan],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        case .blur:
            Rectangle()
                .fill(.ultraThinMaterial.opacity(glassOpacity))
        case .weatherMatch:
            // Mock "Sunny" gradient
            LinearGradient(
                colors: [Color.orange, Color.yellow],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    // Helper to determine alignment based on position
    func alignment(for position: WidgetMetricPosition) -> HorizontalAlignment {
        switch position {
        case .topLeft, .middleLeft, .bottomLeft:
            return .leading
        case .topRight, .middleRight, .bottomRight:
            return .trailing
        default:
            return .center
        }
    }
    
    @ViewBuilder
    func metricView(for position: WidgetMetricPosition) -> some View {
        if let type = config.metrics[position] {
            let align = alignment(for: position)
            
            VStack(alignment: align, spacing: 4) {
                // Content based on type
                switch type {
                case .temperature:
                    if position == .center {
                        Text("24°")
                            .font(font(size: 44, weight: .thin))
                    } else {
                        VStack(alignment: align, spacing: 2) {
                            WidgetIconView(icon: "thermometer.medium", size: 14)
                            Text("24°")
                        }
                        .font(font(size: 14, weight: .bold))
                    }
                    
                case .condition:
                    if position == .center {
                        WidgetIconView(icon: "sun.max.fill", size: 40)
                    } else {
                        WidgetIconView(icon: "sun.max.fill", size: 20)
                    }
                    
                case .uvIndex:
                    metricStack(icon: "sun.max.fill", value: "6", label: "UV", alignment: align)
                    
                case .wind:
                    metricStack(icon: "wind", value: "15", label: "km/h", alignment: align)
                    
                case .humidity:
                    metricStack(icon: "humidity.fill", value: "45%", label: "", alignment: align)
                    
                case .visibility:
                    metricStack(icon: "eye.fill", value: "10km", label: "", alignment: align)
                    
                case .feelsLike:
                    metricStack(icon: "figure.stand", value: "26°", label: "Feels", alignment: align)
                    
                case .precipChance:
                    metricStack(icon: "umbrella.fill", value: "0%", label: "", alignment: align)

                case .rainAmount:
                    metricStack(icon: "drop.fill", value: "2.4", label: "mm", alignment: align)
                    
                case .pressure:
                     metricStack(icon: "barometer", value: "1012", label: "", alignment: align)
                    
                case .highLow:
                    VStack(alignment: align, spacing: 2) {
                        Text("H:28°")
                        Text("L:18°")
                    }
                    .font(font(size: 12, weight: .bold))

                case .dailyForecast:
                    if config.widgetSize == .small {
                        // Compact view for small slots
                        VStack(alignment: align, spacing: 2) {
                            Text("Today").font(font(size: 10, weight: .bold))
                            Image(systemName: "sun.max.fill")
                            Text("28°").font(font(size: 12, weight: .bold))
                        }
                    } else if position == .center || position == .middleLeft || position == .middleRight {
                        HStack(spacing: 8) {
                            DayForecastView(day: "Mon", icon: "sun.max.fill", temp: "28°")
                            DayForecastView(day: "Tue", icon: "cloud.sun.fill", temp: "25°")
                            DayForecastView(day: "Wed", icon: "cloud.rain.fill", temp: "22°")
                        }
                    } else {
                        Image(systemName: "calendar")
                    }

                case .aqi:
                    if position == .center {
                        VStack(spacing: 0) {
                            Text("45")
                                .font(font(size: 28, weight: .heavy))
                            Text("Good")
                                .font(font(size: 10, weight: .medium))
                                .foregroundColor(.green)
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(8)
                    } else {
                        metricStack(icon: "aqi.low", value: "45", label: "AQI", alignment: align)
                    }
                    
                case .temperatureChart:
                     if position == .center || position == .middleLeft || position == .middleRight {
                         PreviewChartView(height: 40)
                     } else {
                         WidgetIconView(icon: "chart.xyaxis.line", size: 20)
                     }
                }
            }
            .foregroundColor(.white)
            .shadow(radius: 2)
        } else {
            // Empty slot hidden as per user request
            Color.clear
        }
    }
    
    func metricStack(icon: String, value: String, label: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            WidgetIconView(icon: icon, size: 14)
            Text(value)
                .font(font(size: 14, weight: .bold))
            if !label.isEmpty {
                Text(label)
                    .font(font(size: 8, weight: .medium))
                    .opacity(0.8)
            }
        }
    }
    
    func font(size: CGFloat, weight: Font.Weight) -> Font {
        switch config.fontStyle {
        case .system: return .system(size: size, weight: weight)
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        case .serif: return .system(size: size, weight: weight, design: .serif)
        case .monospaced: return .system(size: size, weight: weight, design: .monospaced)
        }
    }
    
    @ViewBuilder
    func WidgetIconView(icon: String, size: CGFloat) -> some View {
        switch config.iconStyle {
        case .emoji:
            Text(emoji(for: icon))
                .font(font(size: size, weight: .regular))
        case .realistic:
            // Realistic: SFSymbol with fill, maybe multi-color if possible, or just filled variant
            Image(systemName: realisticIcon(for: icon))
                .symbolRenderingMode(.multicolor)
                .font(font(size: size, weight: .regular))
        case .minimalist:
            // Minimalist: Standard outline/stroke
            Image(systemName: icon)
                .font(font(size: size, weight: .regular))
        }
    }

    func emoji(for systemName: String) -> String {
        // Map SF Symbols to Emojis
        if systemName.contains("sun") { return "☀️" }
        if systemName.contains("moon") { return "🌙" }
        if systemName.contains("cloud.sun") { return "⛅️" }
        if systemName.contains("cloud.rain") { return "🌧️" }
        if systemName.contains("cloud.bolt") { return "⛈️" }
        if systemName.contains("snow") { return "❄️" }
        if systemName.contains("wind") { return "💨" }
        if systemName.contains("thermometer") { return "🌡️" }
        if systemName.contains("umbrella") { return "☂️" }
        if systemName.contains("humidity") { return "💧" }
        if systemName.contains("eye") { return "👁️" }
        if systemName.contains("barometer") { return "⏲️" }
        if systemName.contains("aqi") { return "😷" }
        if systemName.contains("figure") { return "🧍" }
        if systemName.contains("speedometer") { return "🚗" }
        return "❓"
    }

    func realisticIcon(for systemName: String) -> String {
        // Ensure we use filled variants where available
        if systemName.contains(".fill") { return systemName }
        
        // Handle cases where .fill variant might not exist or is named differently
        if systemName == "wind" { return "wind" } // No fill for wind
        if systemName == "barometer" { return "barometer" } // No fill
        
        return systemName + ".fill"
    }
    
    @ViewBuilder
    func DayForecastView(day: String, icon: String, temp: String) -> some View {
        VStack(spacing: 2) {
            Text(day).font(font(size: 10, weight: .medium)).opacity(0.8)
            WidgetIconView(icon: icon, size: 14)
            Text(temp).font(font(size: 12, weight: .bold))
        }
    }
}

struct PreviewChartView: View {
    let height: CGFloat
    
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let padding: CGFloat = 4
            let viewHeight = proxy.size.height - (padding * 2)
            
            // Gradient Fill
            Path { path in
                path.move(to: CGPoint(x: 0, y: viewHeight + padding)) // Bottom Left
                
                for x in stride(from: 0, to: Int(width), by: 5) {
                    let normalizedX = CGFloat(x) / width
                    let radians = normalizedX * 2 * .pi
                    let normalizedY = (sin(radians) + 1) / 2 // 0...1
                    let y = viewHeight - (normalizedY * viewHeight) + padding
                    path.addLine(to: CGPoint(x: CGFloat(x), y: y))
                }
                
                path.addLine(to: CGPoint(x: width, y: viewHeight + padding)) // Bottom Right
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [Color.white.opacity(0.4), Color.white.opacity(0.0)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
            // Line Stroke
            Path { path in
                for x in stride(from: 0, to: Int(width), by: 5) {
                    let normalizedX = CGFloat(x) / width
                    let radians = normalizedX * 2 * .pi
                    let normalizedY = (sin(radians) + 1) / 2 // 0...1
                    let y = viewHeight - (normalizedY * viewHeight) + padding
                    
                    if x == 0 {
                        path.move(to: CGPoint(x: CGFloat(x), y: y))
                    } else {
                        path.addLine(to: CGPoint(x: CGFloat(x), y: y))
                    }
                }
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
        }
        .frame(height: height)
    }
}
