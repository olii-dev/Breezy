//
//  PollenDashboardCard.swift
//  Breezy
//
//  In-app dashboard card for pollen levels + allergy-risk rating.
//  Pollen data is Open-Meteo only and only within the CAMS European
//  domain; elsewhere (and on WeatherKit) the dashboard renders an
//  unavailable/unsupported state.
//

import SwiftUI

struct PollenDashboardCard: View {
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
        let pollen = weather.metrics?.pollen

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Pollen", systemImage: "allergens")
                    .font(.caption.weight(.bold))
                    .foregroundColor(textColor.opacity(0.6))
                Spacer()
            }

            if let pollen {
                // Risk pill — always shown when we have pollen data.
                HStack(spacing: 10) {
                    Circle()
                        .fill(pollen.level.color)
                        .frame(width: 10, height: 10)
                    Text(pollen.levelLabel)
                        .font(.title3.weight(.bold))
                        .foregroundColor(textColor)
                    if let dominant = pollen.dominantSpeciesName {
                        Text("Main: \(dominant)")
                            .font(.caption)
                            .foregroundColor(textColor.opacity(0.7))
                    }
                }

                Text(pollen.levelDetail)
                    .font(.caption)
                    .foregroundColor(textColor.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)

                let species = PollenRatingEngine.species(
                    alderPollen: pollen.alderPollen,
                    birchPollen: pollen.birchPollen,
                    grassPollen: pollen.grassPollen,
                    mugwortPollen: pollen.mugwortPollen,
                    olivePollen: pollen.olivePollen,
                    ragweedPollen: pollen.ragweedPollen
                )

                if style == "compact" {
                    // Only the species actually reporting something.
                    let active = species.filter { $0.value != nil }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(active) { entry in
                                PollenSpeciesChip(entry: entry, textColor: textColor)
                            }
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(species) { entry in
                            PollenSpeciesTile(entry: entry, textColor: textColor)
                        }
                    }
                }
            } else {
                Text("Pollen levels are available across Europe with Open-Meteo. Switch your weather source and travel (or search) inside Europe to see them.")
                    .font(.caption)
                    .foregroundColor(textColor.opacity(0.68))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .softGlassCard()
    }
}

private struct PollenSpeciesTile: View {
    let entry: PollenSpecies
    let textColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(textColor.opacity(0.62))
                Spacer()
                Circle()
                    .fill(entry.level.color)
                    .frame(width: 8, height: 8)
            }

            Text(formattedValue)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(textColor)

            // Intensity bar: low → veryHigh across the tile width.
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(entry.level.color)
                        .frame(width: max(4, proxy.size.width * intensityFraction))
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusS)
                .fill(Color.white.opacity(0.08))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.name) pollen: \(accessibilityValue)")
    }

    private var formattedValue: String {
        guard let value = entry.value else { return "—" }
        return String(format: "%.0f /m³", value)
    }

    /// Fraction of the species' own "very high" threshold, capped at 1.
    private var intensityFraction: CGFloat {
        guard let value = entry.value, value > 0 else { return 0 }
        let ceiling: Double
        switch entry.name {
        case "Birch":    ceiling = 60
        case "Grass":    ceiling = 50
        case "Alder":    ceiling = 60
        case "Mugwort":  ceiling = 30
        case "Olive":    ceiling = 40
        case "Ragweed":  ceiling = 30
        default:         ceiling = 50
        }
        return CGFloat(min(1, value / ceiling))
    }

    private var accessibilityValue: String {
        guard let value = entry.value else { return "no data" }
        return "\(entry.level.label.lowercased()), \(Int(value)) grains per cubic metre"
    }
}

private struct PollenSpeciesChip: View {
    let entry: PollenSpecies
    let textColor: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(entry.level.color)
                .frame(width: 7, height: 7)
            Text(entry.name)
                .font(.caption2.weight(.semibold))
                .foregroundColor(textColor.opacity(0.75))
            Text(formattedValue)
                .font(.caption2)
                .foregroundColor(textColor.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color.white.opacity(0.08))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.name) pollen: \(entry.level.label)")
    }

    private var formattedValue: String {
        guard let value = entry.value else { return "—" }
        return String(format: "%.0f /m³", value)
    }
}
