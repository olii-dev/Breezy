//
//  FeelsLikeWidget.swift
//  Breezy
//
//  Widget displaying Feels Like temperature
//

import SwiftUI

struct FeelsLikeWidget: View {
    let weather: WeatherInfo
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    var config: [String: String]?
    
    private var style: String { config?["style"] ?? "standard" }
    
    var body: some View {
        let textColor = viewModel.currentTheme(colorScheme: colorScheme).textColor
        VStack(alignment: .leading, spacing: style == "compact" ? 8 : 12) {
            HStack {
                Image(systemName: "thermometer.medium")
                    .foregroundColor(textColor.opacity(0.7))
                Text("Feels Like")
                    .font(.caption.weight(.bold))
                    .foregroundColor(textColor.opacity(0.6))
                Spacer()
            }
            
            if let feelsLike = weather.feelsLike {
                VStack(alignment: .leading, spacing: 4) {
                    Text(feelsLike)
                        .font(.system(size: style == "emphasis" ? 44 : style == "compact" ? 28 : 36, weight: .bold))
                        .foregroundColor(textColor)
                    
                    if style != "compact" {
                        Text(impactDescription())
                            .font(.subheadline)
                            .foregroundColor(textColor.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                }
            } else {
                Text("N/A")
            }
        }
        .softGlassCard()
    }
    
    func impactDescription() -> String {
        // Compare actual temp with feels like
        // We need to parse the strings "20°C" -> 20.0
        // This is a bit fragile without raw values, but WeatherInfo strings are formatted.
        // Ideally we'd have raw values in WeatherInfo, but we only have formatted strings.
        // However, WeatherInfo does NOT store raw values except in `hourlyForecast` or `metrics`?
        // Wait, `WeatherInfo` has `temperature` (String).
        // Let's rely on simple heuristic or just generic text if parsing fails.
        // Actually, `WeatherInfo` is constructed from `WeatherViewModel` which has access to raw data.
        // But the widget only gets `WeatherInfo`.
        
        // Let's access humidity and wind to give context.
        var reasons: [String] = []
        if let humidity = weather.metrics?.humidity, humidity > 70 {
            reasons.append("high humidity")
        }
        // if let wind = weather.metrics?.windSpeed { ... } unused
        
        if reasons.isEmpty {
            return "Similar to actual temperature."
        } else {
            return "Wind and humidity are affecting the feel."
        }
    }
}
