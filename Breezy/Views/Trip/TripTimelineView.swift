//
//  TripTimelineView.swift
//  Breezy
//
//  Journey timeline — hero of Trip Mode.
//

import SwiftUI

struct TripTimelineView: View {
    let samples: [TripSamplePoint]
    let theme: WeatherTheme
    let glassOpacity: Double
    var isLoading: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
            HStack {
                Text("Journey")
                    .font(.headline)
                    .foregroundStyle(theme.textColor)
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(theme.textColor)
                }
            }

            if samples.isEmpty {
                timelineSkeleton
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(samples.enumerated()), id: \.element.id) { index, sample in
                        TripTimelineRow(
                            sample: sample,
                            theme: theme,
                            isFirst: index == 0,
                            isLast: index == samples.count - 1
                        )
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, DesignSystem.spacingS)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                        .fill(.ultraThinMaterial.opacity(glassOpacity))
                )
            }
        }
    }

    private var timelineSkeleton: some View {
        VStack(spacing: 12) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.textColor.opacity(0.08))
                    .frame(height: 56)
            }
        }
        .padding(DesignSystem.spacingM)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                .fill(.ultraThinMaterial.opacity(glassOpacity))
        )
    }
}

private struct TripTimelineRow: View {
    let sample: TripSamplePoint
    let theme: WeatherTheme
    let isFirst: Bool
    let isLast: Bool

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(theme.textColor.opacity(isFirst || isLast ? 0.9 : 0.45))
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)
                if !isLast {
                    Rectangle()
                        .fill(theme.textColor.opacity(0.2))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Self.timeFormatter.string(from: sample.eta))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(theme.textColor)
                        .monospacedDigit()
                    Text(sample.placeLabel)
                        .font(.subheadline)
                        .foregroundStyle(theme.textColor.opacity(0.7))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let weather = sample.weather {
                        Text(weather.formattedTemperature)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.textColor)
                            .fixedSize()
                    } else {
                        Text("--°")
                            .font(.subheadline)
                            .foregroundStyle(theme.textColor.opacity(0.35))
                    }
                }

                HStack(spacing: 10) {
                    if let weather = sample.weather {
                        Text(weather.condition)
                            .font(.caption)
                            .foregroundStyle(theme.textColor.opacity(0.8))
                            .lineLimit(1)
                        Label(weather.formattedPrecipChance, systemImage: "drop.fill")
                            .font(.caption2)
                            .foregroundStyle(theme.textColor.opacity(0.65))
                        Label(weather.formattedWind, systemImage: "wind")
                            .font(.caption2)
                            .foregroundStyle(theme.textColor.opacity(0.65))
                            .lineLimit(1)
                    } else {
                        Text("Fetching weather…")
                            .font(.caption)
                            .foregroundStyle(theme.textColor.opacity(0.4))
                    }
                }

                if !sample.riskFlags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(sample.riskFlags, id: \.self) { flag in
                            Label(flag.title, systemImage: flag.systemImage)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(theme.textColor.opacity(0.12))
                                )
                                .foregroundStyle(theme.textColor.opacity(0.85))
                        }
                    }
                }
            }
            .padding(.vertical, 10)
        }
    }
}
