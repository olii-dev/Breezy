//
//  TripDepartureSlider.swift
//  Breezy
//
//  Departure time scrubber — now → +16 days.
//

import SwiftUI

struct TripDepartureSlider: View {
    let departure: Date
    let range: ClosedRange<Date>
    let theme: WeatherTheme
    let glassOpacity: Double
    var isLoadingWeather: Bool = false
    var offlineHint: Bool = false
    let onChange: (Date) -> Void

    private var span: TimeInterval {
        max(range.upperBound.timeIntervalSince(range.lowerBound), 1)
    }

    private var progress: Double {
        min(1, max(0, departure.timeIntervalSince(range.lowerBound) / span))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Departure")
                    .font(.headline)
                    .foregroundStyle(theme.textColor)
                Spacer()
                if isLoadingWeather {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(theme.textColor)
                }
            }

            Text(formattedDeparture)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.textColor)
                .monospacedDigit()

            Slider(
                value: Binding(
                    get: { progress },
                    set: { newValue in
                        let seconds = span * min(1, max(0, newValue))
                        onChange(range.lowerBound.addingTimeInterval(seconds))
                    }
                ),
                in: 0...1
            )
            .tint(theme.textColor)

            HStack {
                Text("Now")
                Spacer()
                Text("+16 days")
            }
            .font(.caption2)
            .foregroundStyle(theme.textColor.opacity(0.55))

            if offlineHint {
                Text("Showing nearest cached hours. Connect to refresh weather for this departure.")
                    .font(.caption)
                    .foregroundStyle(theme.textColor.opacity(0.7))
            }
        }
        .padding(DesignSystem.spacingM)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                .fill(.ultraThinMaterial.opacity(glassOpacity))
        )
    }

    private var formattedDeparture: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: departure)
    }
}
