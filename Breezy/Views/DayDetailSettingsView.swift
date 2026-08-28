//
//  DayDetailSettingsView.swift
//  Breezy
//
//  Settings for Day Detail View sections
//

import SwiftUI

struct DayDetailSettingsView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    
    private var theme: WeatherTheme {
        viewModel.currentTheme(colorScheme: colorScheme)
    }
    
    var body: some View {
        ZStack {
            AnimatedGradientBackground(colors: [theme.topColor, theme.bottomColor])
            
            ScrollView {
                VStack(spacing: DesignSystem.spacingL) {
                    VStack(alignment: .leading, spacing: DesignSystem.spacingM) {
                        Text("DAILY VIEW ORDER")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(theme.textColor.opacity(0.6))
                            .padding(.horizontal, DesignSystem.spacingM)
                        
                        VStack(spacing: 1) {
                            SettingsToggleRow(
                                title: "Quick Stats",
                                icon: "bolt.fill",
                                color: .yellow,
                                textColor: theme.textColor,
                                isOn: $viewModel.showQuickStatsInDayDetail
                            )

                            Divider()
                                .background(theme.textColor.opacity(0.1))

                            SettingsToggleRow(
                                title: "Temperature Chart",
                                icon: "chart.xyaxis.line",
                                color: .blue,
                                textColor: theme.textColor,
                                isOn: $viewModel.showHourlyChartsInDayDetail
                            )

                            Divider()
                                .background(theme.textColor.opacity(0.1))

                            SettingsToggleRow(
                                title: "Rain Outlook",
                                icon: "cloud.rain.fill",
                                color: .cyan,
                                textColor: theme.textColor,
                                isOn: $viewModel.showPrecipitationChartInDayDetail
                            )

                            Divider()
                                .background(theme.textColor.opacity(0.1))

                            SettingsToggleRow(
                                title: "UV Outlook",
                                icon: "sun.max.fill",
                                color: .orange,
                                textColor: theme.textColor,
                                isOn: $viewModel.showUVChartInDayDetail
                            )
                            
                            Divider()
                                .background(theme.textColor.opacity(0.1))
                            
                            SettingsToggleRow(
                                title: "Hourly Breakdown",
                                icon: "clock.fill",
                                color: .blue,
                                textColor: theme.textColor,
                                isOn: $viewModel.showHourlyBreakdownInDayDetail
                            )

                            Divider()
                                .background(theme.textColor.opacity(0.1))

                            SettingsToggleRow(
                                title: "Sun & Moon",
                                icon: "sun.max.fill",
                                color: .orange,
                                textColor: theme.textColor,
                                isOn: $viewModel.showSunMoonInDayDetail
                            )

                            Divider()
                                .background(theme.textColor.opacity(0.1))

                            SettingsToggleRow(
                                title: "Wind Card",
                                icon: "wind",
                                color: .mint,
                                textColor: theme.textColor,
                                isOn: $viewModel.showWindChartInDayDetail
                            )
                        }
                        .background(theme.textColor.opacity(0.1))
                        .cornerRadius(DesignSystem.radiusM)
                    }
                    .padding(.horizontal, DesignSystem.spacingM)

                    Text("These controls only affect the per-day detail screen opened from the 10-day forecast.")
                        .font(.caption)
                        .foregroundColor(theme.textColor.opacity(0.62))
                        .padding(.horizontal, DesignSystem.spacingM)
                    
                    Spacer(minLength: 40)
                }
                .padding(.top, DesignSystem.spacingM)
            }
        }
        .navigationTitle("Daily View")
        .navigationBarTitleDisplayMode(.inline)
    }
}
