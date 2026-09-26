//
//  TripShareCard.swift
//  Breezy
//
//  Shareable trip summary card — route, drive stats, and the weather at
//  waypoints along the way, rendered to an image for the share sheet.
//

import SwiftUI

struct TripShareCardView: View {
    let route: TripRouteOption
    let originName: String
    let destinationName: String
    let departure: Date
    let arrivalBrief: String
    let theme: WeatherTheme
    let glassOpacity: Double

    @Environment(\.dismiss) private var dismiss
    @State private var renderedImage: Image?

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground(colors: [theme.topColor, theme.bottomColor])

                VStack(spacing: 24) {
                    Spacer()

                    shareCardContent
                        .padding(.horizontal, 24)

                    Spacer()

                    if let renderedImage {
                        renderedImage
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .shadow(radius: 10)
                    }

                    ShareLink(
                        item: renderedImage ?? Image(systemName: "photo"),
                        preview: SharePreview(
                            "Trip to \(destinationName)",
                            image: renderedImage ?? Image(systemName: "photo")
                        )
                    ) {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Share")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .foregroundStyle(theme.textColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.ultraThinMaterial.opacity(glassOpacity))
                        )
                        .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(theme.textColor)
                        .fontWeight(.bold)
                }
            }
            .task { renderCard() }
        }
    }

    // MARK: - Visible card

    private var shareCardContent: some View {
        tripCard
            .background(
                ImageRendererView(content: AnyView(tripCardRenderable))
                    .opacity(0)
            )
    }

    private var tripCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(originName) → \(destinationName)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme.textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Text(departure, style: .date)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textColor.opacity(0.5))
            }

            HStack(spacing: 18) {
                Label(route.travelTimeFormatted, systemImage: "clock")
                Label(String(format: "%.0f km", route.distanceKilometers), systemImage: "road.lanes")
                Label(
                    departure.formatted(date: .omitted, time: .shortened),
                    systemImage: "car.fill"
                )
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme.textColor.opacity(0.75))
            .symbolRenderingMode(.hierarchical)

            Divider()
                .background(theme.textColor.opacity(0.2))

            // Waypoint weather strip
            HStack(alignment: .top, spacing: 8) {
                ForEach(waypointSamples) { sample in
                    VStack(spacing: 4) {
                        Text(sample.eta.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(theme.textColor.opacity(0.65))
                        Image(systemName: Self.symbol(for: sample.weather))
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(theme.textColor)
                            .symbolRenderingMode(.hierarchical)
                        Text(sample.weather?.formattedTemperature ?? "--")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.textColor)
                        Text(sample.placeLabel)
                            .font(.system(size: 9))
                            .foregroundStyle(theme.textColor.opacity(0.6))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if !arrivalBrief.isEmpty {
                Text(arrivalBrief)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textColor.opacity(0.85))
                    .lineLimit(3)
            }

            HStack {
                Spacer()
                Label("Breezy · On the Way", systemImage: "cloud.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textColor.opacity(0.45))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial.opacity(glassOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(theme.textColor.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Renderable card (fixed size for ImageRenderer)

    private var tripCardRenderable: some View {
        ZStack {
            LinearGradient(
                colors: [theme.topColor, theme.bottomColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: 400, height: 360)

            tripCard
                .padding(16)
        }
    }

    // MARK: - Data shaping

    /// Up to five weather-bearing samples spread evenly along the route,
    /// always including the last one (arrival).
    private var waypointSamples: [TripSamplePoint] {
        let withWeather = route.samples.filter { $0.weather != nil }
        guard withWeather.count > 5 else { return withWeather }

        let stride = Double(withWeather.count - 1) / 4.0
        let picked = (0...4).map { withWeather[min(withWeather.count - 1, Int((Double($0) * stride).rounded()))] }
        return picked
    }

    private static func symbol(for weather: TripWeatherSnapshot?) -> String {
        guard let weather else { return "cloud" }
        let condition = weather.condition.lowercased()
        if condition.contains("thunder") { return "cloud.bolt.fill" }
        if condition.contains("rain") || condition.contains("drizzle") { return "cloud.rain.fill" }
        if condition.contains("shower") { return "cloud.sun.rain.fill" }
        if condition.contains("snow") { return "cloud.snow.fill" }
        if condition.contains("fog") || condition.contains("mist") || condition.contains("haze") { return "cloud.fog.fill" }
        if condition.contains("cloud") || condition.contains("overcast") { return "cloud.fill" }
        if condition.contains("partly") { return "cloud.sun.fill" }
        if condition.contains("clear") || condition.contains("sun") { return "sun.max.fill" }
        return "cloud.fill"
    }

    private func renderCard() {
        let renderer = ImageRenderer(content: tripCardRenderable)
        renderer.scale = 3.0
        if let uiImage = renderer.uiImage {
            renderedImage = Image(uiImage: uiImage)
        }
    }
}
