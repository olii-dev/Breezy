//
//  TripGoNowControls.swift
//  Breezy
//
//  Start / end Live Activity for an active drive (Go Now only).
//

import SwiftUI

struct TripGoNowControls: View {
    let isLive: Bool
    let theme: WeatherTheme
    let glassOpacity: Double
    let canStart: Bool
    var errorMessage: String? = nil
    let onStart: () -> Void
    let onEnd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("On the road")
                .font(.headline)
                .foregroundStyle(theme.textColor)

            Text(isLive
                 ? "Live Activity is on your Lock Screen and Dynamic Island. GPS-lite updates weather ahead without draining your battery."
                 : "Go Now starts a Live Activity. It only appears while you’re driving — ending the trip clears it.")
                .font(.caption)
                .foregroundStyle(theme.textColor.opacity(0.65))

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Button {
                if isLive {
                    onEnd()
                } else {
                    onStart()
                }
            } label: {
                Label(
                    isLive ? "End trip" : "Go Now",
                    systemImage: isLive ? "stop.circle.fill" : "bolt.car.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(theme.textColor)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                        .fill(.ultraThinMaterial.opacity(min(1, glassOpacity + 0.2)))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                                .stroke(theme.textColor.opacity(0.28), lineWidth: 1)
                        )
                )
            }
            .disabled(!canStart && !isLive)
            .opacity((!canStart && !isLive) ? 0.45 : 1)
        }
        .padding(DesignSystem.spacingM)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                .fill(.ultraThinMaterial.opacity(glassOpacity))
        )
    }
}
