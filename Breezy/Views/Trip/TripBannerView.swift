//
//  TripBannerView.swift
//  Breezy
//
//  Floating dashboard banner while a Go Now drive is active — the dashboard
//  finally admits a trip is underway.
//

import SwiftUI
import Combine

struct TripBannerView: View {
    let theme: WeatherTheme
    let glassOpacity: Double
    var onTap: () -> Void

    /// The manager writes the snapshot on every GPS fix; re-read on a light
    /// timer so the banner stays current while the dashboard is visible.
    private let snapshotTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    @State private var snapshot = TripStore.goNowSnapshot

    var body: some View {
        Button {
            HapticsManager.shared.impact(style: .light)
            onTap()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbolName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: 1) {
                    Text("On the way to \(snapshot.destinationName)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.textColor)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(theme.textColor.opacity(0.65))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if let arrival = snapshot.arrival {
                    Text(timerInterval: Date()...max(Date().addingTimeInterval(60), arrival), countsDown: true)
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.textColor)
                        .frame(maxWidth: 64)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                    .fill(.ultraThinMaterial.opacity(glassOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                    .stroke(tint.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onReceive(snapshotTimer) { _ in
            snapshot = TripStore.goNowSnapshot
        }
        .onAppear {
            snapshot = TripStore.goNowSnapshot
        }
    }

    private var symbolName: String {
        if snapshot.isOffRoute { return "location.slash" }
        return snapshot.weatherAheadSymbolName ?? "car.fill"
    }

    private var tint: Color {
        if snapshot.isOffRoute { return .gray }
        if snapshot.weatherAheadSymbolName == "cloud.bolt.rain.fill" { return .yellow }
        return .cyan
    }

    private var subtitle: String {
        if snapshot.isOffRoute { return "Finding the route…" }
        if let ahead = snapshot.weatherAheadText, let minutes = snapshot.weatherAheadMinutes {
            return "\(ahead) in ~\(minutes) min"
        }
        if let next = snapshot.nextAlert { return next }
        return "\(snapshot.condition) · \(snapshot.distanceRemainingText ?? "")"
    }
}
