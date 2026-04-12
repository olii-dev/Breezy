import SwiftUI
import Charts

struct WatchChartsPageView: View {
    let weather: WatchWeatherData
    @EnvironmentObject var viewModel: WatchWeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("Breezy.watch.chartTemperature") private var showTemperature = true
    @AppStorage("Breezy.watch.chartUV") private var showUV = true
    @AppStorage("Breezy.watch.chartWind") private var showWind = true
    @AppStorage("Breezy.watch.chartHumidity") private var showHumidity = true
    
    var body: some View {
        let theme = viewModel.theme(for: weather.condition, isSystemDark: colorScheme == .dark)
        
        ScrollView {
            VStack(spacing: 12) {
                Text("CHARTS")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(theme.textColor.opacity(0.6))
                    .padding(.top, 4)
                
                if showTemperature && !weather.hourlyForecast.isEmpty {
                    WatchTemperatureChartView(
                        hourly: weather.hourlyForecast,
                        textColor: theme.textColor
                    )
                }
                
                if showUV, let uvIndex = weather.uvIndex {
                    WatchUVGaugeView(uvIndex: uvIndex, textColor: theme.textColor)
                }
                
                if showWind, weather.windSpeed != nil {
                    WatchWindDetailView(
                        windSpeed: weather.windSpeed,
                        windDirection: weather.windDirection,
                        textColor: theme.textColor
                    )
                }
                
                if showHumidity {
                    WatchHumidityBarView(
                        humidity: weather.humidity,
                        cloudCover: weather.cloudCover,
                        textColor: theme.textColor
                    )
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .focusable()
    }
}

// MARK: - Temperature Chart

struct WatchTemperatureChartView: View {
    let hourly: [WatchHourlyForecast]
    let textColor: Color
    
    private var temps: [TempPoint] {
        hourly.enumerated().compactMap { index, hour in
            let cleaned = hour.temperature.replacingOccurrences(of: "°", with: "")
                .replacingOccurrences(of: "C", with: "")
                .replacingOccurrences(of: "F", with: "")
            guard let temp = Double(cleaned) else { return nil }
            return TempPoint(index: index, time: hour.time, temp: temp)
        }
    }
    
    @State private var selectedIndex: Int? = nil
    
    private var selectedPoint: TempPoint? {
        guard let idx = selectedIndex, temps.indices.contains(idx) else { return nil }
        return temps[idx]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "thermometer.medium")
                    .font(.caption2)
                Text("Temperature")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if let point = selectedPoint {
                    Text(String(format: "%.0f°", point.temp))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)
                }
            }
            .foregroundColor(textColor.opacity(0.7))
            
            if temps.count >= 2 {
                Chart {
                    ForEach(temps) { point in
                        AreaMark(
                            x: .value("Hour", point.index),
                            y: .value("Temp", point.temp)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.3), Color.orange.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        
                        LineMark(
                            x: .value("Hour", point.index),
                            y: .value("Temp", point.temp)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    
                    if let sel = selectedPoint {
                        RuleMark(x: .value("Selected", sel.index))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .foregroundStyle(textColor.opacity(0.4))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: 6)) { value in
                        AxisValueLabel {
                            if let index = value.as(Int.self), index < hourly.count {
                                Text(hourly[index].time)
                                    .font(.system(size: 8))
                                    .foregroundColor(textColor.opacity(0.5))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3, dash: [2, 3]))
                            .foregroundStyle(textColor.opacity(0.1))
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard let plotFrame = proxy.plotFrame else { return }
                                        let origin = geometry[plotFrame].origin
                                        let locationX = value.location.x - origin.x
                                        if let index: Int = proxy.value(atX: locationX) {
                                            let nearest = temps.min { abs($0.index - index) < abs($1.index - index) }
                                            selectedIndex = nearest?.index
                                        }
                                    }
                                    .onEnded { _ in
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                            selectedIndex = nil
                                        }
                                    }
                            )
                    }
                }
                .frame(height: 80)
            } else {
                Text("Not enough data")
                    .font(.caption2)
                    .foregroundColor(textColor.opacity(0.5))
            }
        }
        .padding(10)
        .background(textColor.opacity(0.08))
        .cornerRadius(12)
    }
}

private struct TempPoint: Identifiable {
    let id = UUID()
    let index: Int
    let time: String
    let temp: Double
}

// MARK: - UV Gauge

struct WatchUVGaugeView: View {
    let uvIndex: Int
    let textColor: Color
    
    private var category: String {
        switch uvIndex {
        case 0...2: return "Low"
        case 3...5: return "Moderate"
        case 6...7: return "High"
        case 8...10: return "Very High"
        default: return "Extreme"
        }
    }
    
    private var uvColor: Color {
        switch uvIndex {
        case 0...2: return .green
        case 3...5: return .yellow
        case 6...7: return .orange
        case 8...10: return .red
        default: return .purple
        }
    }
    
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "sun.max.fill")
                    .font(.caption2)
                Text("UV Index")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
            }
            .foregroundColor(textColor.opacity(0.7))
            
            ZStack {
                Circle()
                    .stroke(textColor.opacity(0.1), lineWidth: 6)
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0, to: min(CGFloat(uvIndex) / 11.0, 1.0))
                    .stroke(uvColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 2) {
                    Text("\(uvIndex)")
                        .font(.system(size: 20, weight: .bold))
                    Text(category)
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(textColor)
            }
        }
        .padding(10)
        .background(textColor.opacity(0.08))
        .cornerRadius(12)
    }
}

// MARK: - Wind Detail

struct WatchWindDetailView: View {
    let windSpeed: String?
    let windDirection: String?
    let textColor: Color
    
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "wind")
                    .font(.caption2)
                Text("Wind")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
            }
            .foregroundColor(textColor.opacity(0.7))
            
            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text(windSpeed ?? "--")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(textColor)
                    Text("Speed")
                        .font(.system(size: 9))
                        .foregroundColor(textColor.opacity(0.5))
                }
                
                if let dir = windDirection {
                    VStack(spacing: 4) {
                        Text(dir)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(textColor)
                        Text("Direction")
                            .font(.system(size: 9))
                            .foregroundColor(textColor.opacity(0.5))
                    }
                }
            }
        }
        .padding(10)
        .background(textColor.opacity(0.08))
        .cornerRadius(12)
    }
}

// MARK: - Humidity & Cloud Cover

struct WatchHumidityBarView: View {
    let humidity: Int?
    let cloudCover: String?
    let textColor: Color
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "humidity.fill")
                    .font(.caption2)
                Text("Conditions")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
            }
            .foregroundColor(textColor.opacity(0.7))
            
            if let humidity = humidity {
                HStack {
                    Text("Humidity")
                        .font(.system(size: 11))
                        .foregroundColor(textColor.opacity(0.7))
                    Spacer()
                    Text("\(humidity)%")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(textColor)
                }
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(textColor.opacity(0.1))
                            .frame(height: 4)
                        Capsule()
                            .fill(Color.blue.opacity(0.6))
                            .frame(width: geo.size.width * CGFloat(humidity) / 100, height: 4)
                    }
                }
                .frame(height: 4)
            }
            
            if let cloud = cloudCover {
                HStack {
                    Text("Cloud Cover")
                        .font(.system(size: 11))
                        .foregroundColor(textColor.opacity(0.7))
                    Spacer()
                    Text(cloud)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(textColor)
                }
            }
        }
        .padding(10)
        .background(textColor.opacity(0.08))
        .cornerRadius(12)
    }
}
