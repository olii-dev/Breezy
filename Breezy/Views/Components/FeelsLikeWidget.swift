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
                Text("Unavailable")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(textColor.opacity(0.55))
            }
        }
        .softGlassCard()
    }
    
    func impactDescription() -> String {
        let actual = parseTemperature(weather.temperature)
        let feels = parseTemperature(weather.feelsLike)
        let delta = (actual != nil && feels != nil) ? (feels! - actual!) : nil

        var reasons: [String] = []
        if let humidity = weather.metrics?.humidity, humidity > 70 {
            reasons.append("high humidity")
        }
        if let windMPS = parseWindMetersPerSecond(weather.metrics?.windSpeed), windMPS >= 4.5 {
            reasons.append("wind")
        }

        if let delta, abs(delta) < 0.75 {
            return "Similar to the actual temperature."
        }

        if reasons.isEmpty {
            if let delta, delta > 0 {
                return "Feels warmer than the air temperature."
            }
            if let delta, delta < 0 {
                return "Feels cooler than the air temperature."
            }
            return "Similar to the actual temperature."
        }

        let reasonText = reasons.joined(separator: " and ")
        if let delta, delta > 0 {
            return "Feels warmer because of \(reasonText)."
        }
        if let delta, delta < 0 {
            return "Feels cooler because of \(reasonText)."
        }
        return "Affected by \(reasonText)."
    }

    private func parseTemperature(_ value: String?) -> Double? {
        guard let value else { return nil }
        let cleaned = value
            .replacingOccurrences(of: "°", with: "")
            .replacingOccurrences(of: "[^0-9.-]", with: "", options: .regularExpression)
        return Double(cleaned)
    }

    private func parseWindMetersPerSecond(_ windSpeed: String?) -> Double? {
        guard let windSpeed else { return nil }
        let lowercased = windSpeed.lowercased()
        let cleaned = lowercased
            .replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        guard let value = Double(cleaned) else { return nil }
        if lowercased.contains("km/h") { return value / 3.6 }
        if lowercased.contains("mph") { return value / 2.23694 }
        if lowercased.contains("knot") { return value / 1.94384 }
        return value // m/s default
    }
}
