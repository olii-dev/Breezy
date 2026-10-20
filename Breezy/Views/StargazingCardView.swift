//
//  StargazingCardView.swift
//  Breezy
//
//  Dashboard card for aurora + night-sky conditions. Data comes from the
//  AuroraKit snapshot the app refreshes alongside every weather fetch
//  (NOAA SWPC Kp + solar wind, local cloud/moon/darkness).
//

import SwiftUI

struct StargazingCardView: View {
    let weather: WeatherInfo
    @ObservedObject var viewModel: WeatherViewModel
    let textColor: Color
    let glassOpacity: Double

    private var snapshot: AuroraKit.Snapshot? { AuroraStore.load() }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let snapshot, let kp = snapshot.kp {
                kpRow(snapshot: snapshot, kp: kp)
                factorRow(snapshot: snapshot)
                Text(snapshot.detail)
                    .font(.caption)
                    .foregroundColor(textColor.opacity(0.6))
            } else {
                Text("Waiting for NOAA space-weather data — it refreshes with each forecast.")
                    .font(.caption)
                    .foregroundColor(textColor.opacity(0.6))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                .fill(.ultraThinMaterial.opacity(glassOpacity))
                .overlay(RoundedRectangle(cornerRadius: DesignSystem.radiusL).stroke(borderColor, lineWidth: 0.5))
        )
        .shadow(color: Color.black.opacity(0.15), radius: 18, x: 0, y: 10)
    }

    private var isActive: Bool { snapshot?.isActive == true }

    private var borderColor: Color {
        isActive ? Color.purple.opacity(0.55) : textColor.opacity(0.18)
    }

    private var header: some View {
        HStack {
            Label("Stargazing", systemImage: "sparkles")
                .font(.caption.weight(.bold))
                .foregroundColor(textColor.opacity(0.6))
            Spacer()
            if let snapshot {
                Text(snapshot.verdict)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill((isActive ? Color.purple : textColor).opacity(0.18)))
                    .foregroundColor(isActive ? .purple : textColor.opacity(0.8))
            }
        }
    }

    private func kpRow(snapshot: AuroraKit.Snapshot, kp: Double) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(textColor.opacity(0.15), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, kp / 9)))
                    .stroke(
                        AngularGradient(
                            colors: [.teal, .green, .yellow, .orange, .red, .purple],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(AuroraKit.formatted(kp))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("Kp")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(textColor.opacity(0.55))
                }
            }
            .frame(width: 74, height: 74)

            VStack(alignment: .leading, spacing: 4) {
                if let required = snapshot.requiredKp {
                    Text("Needs Kp \(AuroraKit.formatted(required)) from your latitude")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(textColor)
                }
                if let bz = snapshot.bzNanoteslas {
                    HStack(spacing: 4) {
                        Image(systemName: bz <= -5 ? "arrow.down.circle.fill" : "minus.circle")
                            .font(.caption)
                            .foregroundColor(bz <= -5 ? .green : textColor.opacity(0.5))
                        Text("Bz \(Int(bz)) nT")
                            .font(.caption)
                            .foregroundColor(textColor.opacity(0.7))
                    }
                }
                if let moon = snapshot.moonIllumination {
                    Text("Moon \(Int((moon * 100).rounded()))% — darker is better")
                        .font(.caption)
                        .foregroundColor(textColor.opacity(0.7))
                }
            }
            Spacer()
        }
    }

    private func factorRow(snapshot: AuroraKit.Snapshot) -> some View {
        HStack(spacing: 8) {
            if let cloud = snapshot.cloudFraction {
                chip(icon: "cloud.fill", text: "\(Int((cloud * 100).rounded()))% cloud",
                     good: cloud < 0.35)
            }
            if let speed = snapshot.solarWindSpeed {
                chip(icon: "wind", text: "\(Int(speed)) km/s", good: speed > 450)
            }
            if !snapshot.isNight {
                chip(icon: "sun.max.fill", text: "daylight", good: false)
            }
            Spacer(minLength: 0)
        }
    }

    private func chip(icon: String, text: String, good: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill((good ? Color.green : textColor).opacity(0.12)))
        .foregroundColor(textColor.opacity(0.85))
    }
}
