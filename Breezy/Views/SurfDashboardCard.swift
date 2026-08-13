//
//  SurfDashboardCard.swift
//  Breezy
//
//  In-app dashboard card for surf conditions + quality rating.
//  Surf data is Open-Meteo only; on WeatherKit the dashboard renders an
//  UnsupportedSourceWidgetCard instead (gated in ContentView.renderWidget).
//

import SwiftUI

struct SurfDashboardCard: View {
    let weather: WeatherInfo
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    var config: [String: String]?

    private var style: String {
        config?["style"] ?? "detailed"
    }

    var body: some View {
        let theme = viewModel.currentTheme(colorScheme: colorScheme)
        let textColor = theme.textColor
        let surf = weather.metrics?.surf

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Surf", systemImage: "figure.surfing")
                    .font(.caption.weight(.bold))
                    .foregroundColor(textColor.opacity(0.6))
                Spacer()
            }

            if let surf {
                // Rating pill — always shown when we have surf data.
                HStack(spacing: 10) {
                    Circle()
                        .fill(surf.rating.color)
                        .frame(width: 10, height: 10)
                    Text(surf.ratingLabel)
                        .font(.title3.weight(.bold))
                        .foregroundColor(textColor)
                    if let height = surf.waveHeightMeters {
                        Text(SurfRatingEngine.heightDescription(height))
                            .font(.caption)
                            .foregroundColor(textColor.opacity(0.7))
                    }
                }

                Text(surf.ratingDetail)
                    .font(.caption)
                    .foregroundColor(textColor.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)

                if style == "compact" {
                    HStack(spacing: 12) {
                        if let wave = formattedHeight(surf.waveHeightMeters) {
                            SurfMetricTile(title: "Wave", value: wave, icon: "water.waves", textColor: textColor)
                        }
                        if let period = formattedPeriod(surf.wavePeriodSeconds) {
                            SurfMetricTile(title: "Period", value: period, icon: "timer", textColor: textColor)
                        }
                        if let temp = formattedSeaTemp(surf.seaTempCelsius) {
                            SurfMetricTile(title: "Sea", value: temp, icon: "thermometer.medium", textColor: textColor)
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        if let wave = formattedHeight(surf.waveHeightMeters) {
                            SurfMetricTile(title: "Wave Height", value: wave, icon: "water.waves", textColor: textColor)
                        }
                        if let period = formattedPeriod(surf.wavePeriodSeconds) {
                            SurfMetricTile(title: "Wave Period", value: period, icon: "timer", textColor: textColor)
                        }
                        if let swell = formattedHeight(surf.swellHeightMeters) {
                            SurfMetricTile(title: "Swell", value: swell, icon: "waveform.path.ecg", textColor: textColor)
                        }
                        if let temp = formattedSeaTemp(surf.seaTempCelsius) {
                            SurfMetricTile(title: "Sea Temp", value: temp, icon: "thermometer.medium", textColor: textColor)
                        }
                    }

                    if let wind = formattedWind(surf.windSpeedMetersPerSecond, direction: surf.windDirectionDegrees) {
                        Text("Wind: \(wind)")
                            .font(.caption)
                            .foregroundColor(textColor.opacity(0.68))
                    }
                }
            } else {
                Text("Surf data is available near the coast. It becomes useful when you are close to the water.")
                    .font(.caption)
                    .foregroundColor(textColor.opacity(0.68))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softGlassCard()
    }

    // MARK: - Formatting (respect user units where possible)

    private func formattedHeight(_ m: Double?) -> String? {
        guard let m else { return nil }
        // Surf heights are conventionally shown in feet or metres; follow the
        // user's precipitation/length preference indirectly via temperature unit
        // is not appropriate, so show metres consistently with Marine Outlook.
        return String(format: "%.1f m", m)
    }

    private func formattedPeriod(_ s: Double?) -> String? {
        guard let s else { return nil }
        return String(format: "%.0f s", s)
    }

    private func formattedSeaTemp(_ celsius: Double?) -> String? {
        guard let celsius else { return nil }
        if viewModel.temperatureUnit == .fahrenheit {
            let f = (celsius * 9.0 / 5.0) + 32.0
            return String(format: "%.0f°F", f)
        }
        return String(format: "%.0f°C", celsius)
    }

    private func formattedWind(_ mps: Double?, direction: Double?) -> String? {
        guard let mps else { return nil }
        let speed = String(format: "%.0f %@", viewModel.windSpeedUnit.convert(mps), viewModel.windSpeedUnit.displayName)
        if let direction {
            return "\(WindDirectionHelper.cardinalDirection(from: direction)) \(speed)"
        }
        return speed
    }
}

private struct SurfMetricTile: View {
    let title: String
    let value: String
    let icon: String
    let textColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.semibold))
                .foregroundColor(textColor.opacity(0.62))
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(textColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusS)
                .fill(Color.white.opacity(0.08))
        )
    }
}
