//
//  UVIndexWidget.swift
//  Breezy
//
//  Widget displaying UV Index
//

import SwiftUI

struct UVIndexWidget: View {
    struct Content {
        let title: String
        let uvIndex: Int?
        let category: String?
        let summary: String?

        init(title: String = "UV Index", uvIndex: Int?, category: String? = nil, summary: String? = nil) {
            self.title = title
            self.uvIndex = uvIndex
            self.category = category
            self.summary = summary
        }
    }

    private let weather: WeatherInfo?
    private let content: Content?
    @ObservedObject var viewModel: WeatherViewModel
    let style: String
    let showsCategory: Bool
    @Environment(\.colorScheme) var colorScheme

    init(weather: WeatherInfo, viewModel: WeatherViewModel, style: String = "standard", showsCategory: Bool = true) {
        self.weather = weather
        self.content = nil
        self.viewModel = viewModel
        self.style = style
        self.showsCategory = showsCategory
    }

    init(content: Content, viewModel: WeatherViewModel, style: String = "standard", showsCategory: Bool = true) {
        self.weather = nil
        self.content = content
        self.viewModel = viewModel
        self.style = style
        self.showsCategory = showsCategory
    }

    private var isEmphasisStyle: Bool {
        style == "emphasis"
    }

    private var isMinimalStyle: Bool {
        style == "minimal"
    }

    private var resolvedTitle: String {
        content?.title ?? "UV Index"
    }

    private var resolvedUVIndex: Int? {
        content?.uvIndex ?? weather?.metrics?.uvIndex
    }

    private var resolvedCategory: String? {
        content?.category ?? weather?.metrics?.uvIndexCategory
    }

    private var resolvedSummary: String? {
        content?.summary
    }
    
    var body: some View {
        let theme = viewModel.currentTheme(colorScheme: colorScheme)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sun.max.fill")
                    .foregroundColor(isEmphasisStyle ? .yellow : theme.textColor.opacity(0.7))
                Text(resolvedTitle)
                    .font(.caption.weight(.bold))
                    .foregroundColor(theme.textColor.opacity(0.6))
                Spacer()
            }
            
            if let uvIndex = resolvedUVIndex {
                VStack(alignment: .leading, spacing: isMinimalStyle ? 10 : 6) {
                    if isMinimalStyle {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(uvIndex)")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundColor(theme.textColor)

                            if showsCategory {
                                Text(resolvedCategory ?? category(for: uvIndex))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(theme.textColor.opacity(0.78))
                            }

                            Spacer()
                        }
                    } else {
                        Text("\(uvIndex)")
                            .font(.system(size: isEmphasisStyle ? 42 : 36, weight: .bold))
                            .foregroundColor(theme.textColor)

                        if showsCategory {
                            Text(resolvedCategory ?? category(for: uvIndex))
                                .font(.headline)
                                .foregroundColor(theme.textColor)
                        }
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: isEmphasisStyle ? 8 : 6)
                            
                            Capsule()
                                .fill(color(for: uvIndex))
                                .frame(width: min(CGFloat(uvIndex) / 11.0 * geo.size.width, geo.size.width), height: isEmphasisStyle ? 8 : 6)
                        }
                    }
                    .frame(height: isEmphasisStyle ? 8 : 6)
                    .padding(.top, 8)

                    if !isMinimalStyle {
                        Text(resolvedSummary ?? uvSummary(for: uvIndex))
                            .font(.caption)
                            .foregroundColor(theme.textColor.opacity(0.7))
                            .padding(.top, 4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text(resolvedSummary ?? "No UV data available.")
                    .font(.caption)
                    .foregroundColor(theme.textColor.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .softGlassCard()
    }
    
    func category(for uv: Int) -> String {
        switch uv {
        case 0...2: return "Low"
        case 3...5: return "Moderate"
        case 6...7: return "High"
        case 8...10: return "Very High"
        default: return "Extreme"
        }
    }
    
    func color(for uv: Int) -> Color {
        switch uv {
        case 0...2: return .green
        case 3...5: return .yellow
        case 6...7: return .orange
        case 8...10: return .red
        default: return .purple
        }
    }
    
    func uvSummary(for uv: Int) -> String {
        switch uv {
        case 0...2: return "Low intensity conditions right now."
        case 3...5: return "Moderate intensity through the brightest part of the day."
        case 6...7: return "High intensity conditions are in place."
        case 8...10: return "Very high intensity conditions at the moment."
        default: return "Extreme UV intensity is currently active."
        }
    }
}
