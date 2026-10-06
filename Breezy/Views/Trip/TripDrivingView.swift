//
//  TripDrivingView.swift
//  Breezy
//
//  The in-app screen for a live Go Now drive: weather-ahead hero, ticking
//  arrival, route progress and what's coming up next on the road.
//

import SwiftUI
import Combine

struct TripDrivingView: View {
    @ObservedObject var tripVM: TripViewModel
    let theme: WeatherTheme
    let glassOpacity: Double

    /// Snapshot refresh cadence — the manager writes the app-group snapshot
    /// on every accepted GPS fix; the view re-reads it on a light timer.
    private let snapshotTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    @State private var snapshot = TripStore.goNowSnapshot

    var body: some View {
        VStack(spacing: DesignSystem.spacingL) {
            heroCard
            arrivalCard
            progressCard
            upcomingCard
            endButton
        }
        .onReceive(snapshotTimer) { _ in
            snapshot = TripStore.goNowSnapshot
        }
        .onAppear {
            snapshot = TripStore.goNowSnapshot
        }
    }

    // MARK: - Cards

    private var heroCard: some View {
        HStack(spacing: 12) {
            Image(systemName: heroSymbol)
                .font(.largeTitle)
                .foregroundStyle(heroColor)

            VStack(alignment: .leading, spacing: 2) {
                if snapshot.isOffRoute {
                    Text("Finding the route…")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.textColor)
                    Text("GPS will pick the route back up automatically")
                        .font(.caption)
                        .foregroundStyle(theme.textColor.opacity(0.6))
                } else if let ahead = snapshot.weatherAheadText {
                    Text(ahead)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.textColor)
                        .lineLimit(2)
                    if let minutes = snapshot.weatherAheadMinutes {
                        Text("in about \(minutes) min of driving")
                            .font(.caption)
                            .foregroundStyle(theme.textColor.opacity(0.6))
                    }
                } else {
                    Text("\(snapshot.condition) \(snapshot.temperatureText)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(theme.textColor)
                    Text("Nothing risky ahead — smooth driving")
                        .font(.caption)
                        .foregroundStyle(theme.textColor.opacity(0.6))
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
        .background(cardBackground)
    }

    private var arrivalCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if let arrival = snapshot.arrival {
                    Text(timerInterval: Date()...max(Date().addingTimeInterval(60), arrival), countsDown: true)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textColor)
                } else {
                    Text(snapshot.etaText)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textColor)
                }
                Text("until you arrive in \(snapshot.destinationName)")
                    .font(.caption)
                    .foregroundStyle(theme.textColor.opacity(0.6))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(snapshot.etaText)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textColor)
                if snapshot.isOffline {
                    Label("Offline", systemImage: "wifi.slash")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else {
                    Label("Live GPS", systemImage: "location.fill")
                        .font(.caption2)
                        .foregroundStyle(theme.textColor.opacity(0.6))
                }
            }
        }
        .padding()
        .background(cardBackground)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.textColor.opacity(0.2))
                        .frame(height: 8)
                    Capsule()
                        .fill(.cyan)
                        .frame(width: max(8, proxy.size.width * CGFloat(min(max(snapshot.progress, 0), 1))), height: 8)
                }
            }
            .frame(height: 8)

            HStack {
                Text(snapshot.originName)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(Int((snapshot.progress * 100).rounded()))% driven")
                    .foregroundStyle(theme.textColor.opacity(0.6))
                Spacer(minLength: 4)
                Text(snapshot.destinationName)
                    .lineLimit(1)
            }
            .font(.caption2)
            .foregroundStyle(theme.textColor.opacity(0.6))

            if let remaining = snapshot.distanceRemainingText {
                Text(remaining)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.textColor.opacity(0.8))
            }
        }
        .padding()
        .background(cardBackground)
    }

    private var upcomingCard: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
            Text("COMING UP")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.textColor.opacity(0.6))

            let upcoming = upcomingSamples.prefix(3)
            if upcoming.isEmpty {
                Text("Approaching \(snapshot.destinationName)")
                    .font(.subheadline)
                    .foregroundStyle(theme.textColor.opacity(0.7))
            } else {
                ForEach(Array(upcoming), id: \.id) { sample in
                    HStack(spacing: 10) {
                        Image(systemName: sampleSymbol(sample))
                            .foregroundStyle(sampleColor(sample))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(sampleTitle(sample))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(theme.textColor)
                            Text(sample.eta, formatter: Self.timeFormatter)
                                .font(.caption2)
                                .foregroundStyle(theme.textColor.opacity(0.5))
                        }
                        Spacer()
                        if let weather = sample.weather {
                            Text("\(weather.formattedTemperature) · \(weather.formattedPrecipChance) rain")
                                .font(.caption)
                                .foregroundStyle(theme.textColor.opacity(0.6))
                        }
                    }
                }
            }
        }
        .padding()
        .background(cardBackground)
    }

    private var endButton: some View {
        Button {
            HapticsManager.shared.impact(style: .medium)
            tripVM.endGoNow()
        } label: {
            HStack {
                Image(systemName: "stop.circle.fill")
                Text("End Trip")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                    .fill(.red.opacity(0.2))
            )
            .foregroundStyle(.red)
        }
    }

    // MARK: - Helpers

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: DesignSystem.radiusM)
            .fill(.ultraThinMaterial.opacity(glassOpacity))
    }

    private var upcomingSamples: [TripSamplePoint] {
        guard let route = tripVM.selectedRoute ?? TripStore.goNowRoute else { return [] }
        let driven = route.distanceMeters * snapshot.progress
        return route.samples.filter { $0.distanceFromStartMeters >= driven + 500 }
    }

    private var heroSymbol: String {
        if snapshot.isOffRoute { return "location.slash" }
        return snapshot.weatherAheadSymbolName ?? "car.fill"
    }

    private var heroColor: Color {
        if snapshot.isOffRoute { return .gray }
        guard let symbol = snapshot.weatherAheadSymbolName else { return .cyan }
        switch symbol {
        case "cloud.bolt.rain.fill": return .yellow
        case "snowflake": return .blue
        case "eye.slash.fill": return .gray
        case "wind": return .teal
        default: return .cyan
        }
    }

    private func sampleSymbol(_ sample: TripSamplePoint) -> String {
        if let flag = sample.riskFlags.first { return flag.systemImage }
        if let weather = sample.weather {
            return TripWeatherSnapshot.symbolName(for: weather.condition)
        }
        return "car.fill"
    }

    private func sampleColor(_ sample: TripSamplePoint) -> Color {
        if sample.riskFlags.contains(.storms) { return .yellow }
        if sample.riskFlags.isEmpty { return .cyan }
        return .orange
    }

    private func sampleTitle(_ sample: TripSamplePoint) -> String {
        if let flag = sample.riskFlags.first {
            return "\(flag.title)\(sample.placeLabel.isEmpty ? "" : " near \(sample.placeLabel)")"
        }
        if let weather = sample.weather {
            return "\(weather.condition)\(sample.placeLabel.isEmpty ? "" : " near \(sample.placeLabel)")"
        }
        return sample.placeLabel.isEmpty ? "On the road" : sample.placeLabel
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
