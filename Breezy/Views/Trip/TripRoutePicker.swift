//
//  TripRoutePicker.swift
//  Breezy
//
//  Alternate routes ranked by weather risk.
//

import SwiftUI

struct TripRoutePicker: View {
    let routes: [TripRouteOption]
    let selectedID: UUID?
    let theme: WeatherTheme
    let glassOpacity: Double
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
            Text("Routes")
                .font(.headline)
                .foregroundStyle(theme.textColor)

            Text("Ranked by weather risk — lower is calmer.")
                .font(.caption)
                .foregroundStyle(theme.textColor.opacity(0.6))

            VStack(spacing: 8) {
                ForEach(Array(routes.enumerated()), id: \.element.id) { index, route in
                    Button {
                        onSelect(route.id)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(route.name.isEmpty ? "Route \(index + 1)" : route.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(theme.textColor)
                                    .lineLimit(1)
                                Text("\(route.travelTimeFormatted) · \(String(format: "%.0f km", route.distanceKilometers))")
                                    .font(.caption)
                                    .foregroundStyle(theme.textColor.opacity(0.65))
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(riskLabel(route.riskScore))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(theme.textColor)
                                Text(String(format: "%.1f", route.riskScore))
                                    .font(.caption2)
                                    .foregroundStyle(theme.textColor.opacity(0.5))
                            }
                            Image(systemName: selectedID == route.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(theme.textColor.opacity(selectedID == route.id ? 0.95 : 0.35))
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                                .fill(.ultraThinMaterial.opacity(glassOpacity * (selectedID == route.id ? 1.1 : 0.75)))
                                .overlay(
                                    RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                                        .stroke(theme.textColor.opacity(selectedID == route.id ? 0.35 : 0.1), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func riskLabel(_ score: Double) -> String {
        switch score {
        case ..<4: return "Calm"
        case ..<10: return "Mixed"
        case ..<18: return "Risky"
        default: return "Rough"
        }
    }
}
