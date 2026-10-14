//
//  WidgetBuilderView.swift
//  Breezy
//
//  Created for Custom Widget Builder
//

import SwiftUI

struct WidgetBuilderView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    // Config Store
    @StateObject private var store = WidgetConfigStore.shared

    // Temporary state strictly for editing before saving
    @State private var draftConfig: CustomWidgetConfiguration
    @State private var showResetAlert = false
    @State private var showDeleteAlert = false

    init(viewModel: WeatherViewModel) {
        self.viewModel = viewModel
        let initial = WidgetConfigStore.shared.selectedDesign ?? CustomWidgetConfiguration.default
        _draftConfig = State(initialValue: initial)
    }

    /// True when the draft edits a design that already exists in the store.
    private var isEditingSavedDesign: Bool {
        store.designs.contains { $0.id == draftConfig.id }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Theme Background
                let theme = viewModel.currentTheme(colorScheme: colorScheme)
                AnimatedGradientBackground(colors: [theme.topColor, theme.bottomColor])

                ScrollView(showsIndicators: false) {
                    VStack(spacing: DesignSystem.spacingXL) {
                        designsSection(theme: theme)
                        previewArea(theme: theme)
                        layoutSection(theme: theme)
                        appearanceSection(theme: theme)
                        optionsSection(theme: theme)
                        resetButton(theme: theme)
                    }
                    .padding(DesignSystem.spacingM)
                }
            }
            .navigationTitle("Widget Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        HapticsManager.shared.notification(type: .success)
                        store.save(draftConfig)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .foregroundColor(viewModel.currentTheme(colorScheme: colorScheme).textColor)
                }
            }
        }
    }

    // MARK: - Designs

    @ViewBuilder
    func designsSection(theme: WeatherTheme) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingM) {
            StudioHeader(title: "DESIGNS", icon: "square.grid.2x2.fill", theme: theme)

            // Saved designs — each Home Screen widget can pick one of these.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.designs) { design in
                        Button {
                            HapticsManager.shared.impact(style: .light)
                            withAnimation { draftConfig = design }
                        } label: {
                            HStack(spacing: 6) {
                                if design.id == store.selectedID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2)
                                }
                                Text(design.name)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(
                                Capsule().fill(draftConfig.id == design.id ? Color.blue : Color.white.opacity(0.2))
                            )
                            .overlay(
                                Capsule().stroke(design.id == store.selectedID ? Color.blue.opacity(0.7) : Color.clear, lineWidth: 1)
                            )
                            .foregroundColor(draftConfig.id == design.id ? .white : theme.textColor)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)

            // Name of the design being edited
            VStack(alignment: .leading, spacing: 6) {
                Text("Design Name")
                    .font(.caption)
                    .foregroundColor(theme.textColor.opacity(0.6))
                    .padding(.leading, 4)
                TextField("My Widget", text: $draftConfig.name)
                    .font(.subheadline)
                    .foregroundColor(theme.textColor)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.2)))
            }

            HStack(spacing: 12) {
                Button {
                    HapticsManager.shared.impact(style: .light)
                    var newDesign = CustomWidgetConfiguration.default
                    newDesign.name = "Design \(store.designs.count + 1)"
                    newDesign.widgetSize = draftConfig.widgetSize
                    withAnimation { draftConfig = newDesign }
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)

                Button {
                    HapticsManager.shared.impact(style: .light)
                    withAnimation {
                        draftConfig.id = UUID()
                        draftConfig.name = "\(draftConfig.name) Copy"
                    }
                } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)

                if isEditingSavedDesign && store.designs.count > 1 {
                    Button(role: .destructive) {
                        showDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }

            Text("Home Screen: long-press a Widget Studio widget → Edit Widget to pick which design it shows.")
                .font(.caption2)
                .foregroundColor(theme.textColor.opacity(0.5))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
        .alert("Delete Design?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let saved = store.designs.first(where: { $0.id == draftConfig.id }) {
                    store.delete(saved)
                }
                if let next = store.selectedDesign ?? store.designs.first {
                    draftConfig = next
                } else {
                    draftConfig = CustomWidgetConfiguration.default
                }
            }
        } message: {
            Text("\"\(draftConfig.name)\" will be removed. Widgets showing it fall back to your active design.")
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    func previewArea(theme: WeatherTheme) -> some View {
        VStack(spacing: 16) {
            // Size Selector
            Picker("Size", selection: $draftConfig.widgetSize) {
                Text("Small").tag(WidgetSize.small)
                Text("Medium").tag(WidgetSize.medium)
                Text("Large").tag(WidgetSize.large)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 40)
            .onChange(of: draftConfig.widgetSize) { _, _ in
                HapticsManager.shared.selectionChanged()
            }

            Text("LIVE PREVIEW")
                .font(.caption.weight(.bold))
                .foregroundColor(theme.textColor.opacity(0.6))
                .tracking(1)

            WidgetPreviewView(config: draftConfig)
                .padding(.bottom, draftConfig.widgetSize == .large ? 18 : 8)
                .frame(maxWidth: .infinity, minHeight: previewHeight + (draftConfig.widgetSize == .large ? 28 : 12), alignment: .top)
                .id(draftConfig.fontStyle) // Force redraw when font changes
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: draftConfig.widgetSize)
        }
        .padding(.top, 20)
    }

    var previewWidth: CGFloat {
        switch draftConfig.widgetSize {
        case .small: return 160
        case .medium: return 330
        case .large: return 330
        }
    }

    var previewHeight: CGFloat {
        switch draftConfig.widgetSize {
        case .small: return 160
        case .medium: return 160
        case .large: return 345
        }
    }

    @ViewBuilder
    func layoutSection(theme: WeatherTheme) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingM) {
            StudioHeader(title: "LAYOUT", icon: "rectangle.grid.1x2.fill", theme: theme)

            // Layout Style — all four; the widget renderer supports them all.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(WidgetLayout.allCases, id: \.self) { layout in
                        Button {
                            HapticsManager.shared.impact(style: .light)
                            withAnimation { draftConfig.layoutStyle = layout }
                        } label: {
                                    Text(layout.displayName)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(draftConfig.layoutStyle == layout ? .white : theme.textColor)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(draftConfig.layoutStyle == layout ? Color.blue : Color.white.opacity(0.2))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(draftConfig.layoutStyle == layout ? Color.blue : theme.textColor.opacity(0.1), lineWidth: 1)
                                        )
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)

            // Content Pickers
            VStack(spacing: DesignSystem.spacingS) {
                switch draftConfig.layoutStyle {
                case .minimal:
                     MetricPickerRow(title: "Center Content", position: .center, config: $draftConfig, theme: theme)
                case .split:
                     HStack(spacing: 12) {
                         MetricPickerRow(title: "Top Left", position: .topLeft, config: $draftConfig, theme: theme)
                         MetricPickerRow(title: "Top Right", position: .topRight, config: $draftConfig, theme: theme)
                     }
                     MetricPickerRow(title: "Middle Left", position: .middleLeft, config: $draftConfig, theme: theme)
                     MetricPickerRow(title: "Middle Right", position: .middleRight, config: $draftConfig, theme: theme)
                     HStack(spacing: 12) {
                         MetricPickerRow(title: "Bottom Left", position: .bottomLeft, config: $draftConfig, theme: theme)
                         MetricPickerRow(title: "Bottom Right", position: .bottomRight, config: $draftConfig, theme: theme)
                     }
                case .list:
                     HStack(spacing: 12) {
                         MetricPickerRow(title: "Row 1", position: .topLeft, config: $draftConfig, theme: theme)
                         MetricPickerRow(title: "Row 2", position: .topCenter, config: $draftConfig, theme: theme)
                     }
                     HStack(spacing: 12) {
                         MetricPickerRow(title: "Row 3", position: .topRight, config: $draftConfig, theme: theme)
                         MetricPickerRow(title: "Row 4", position: .middleLeft, config: $draftConfig, theme: theme)
                     }
                     HStack(spacing: 12) {
                         MetricPickerRow(title: "Row 5", position: .middleRight, config: $draftConfig, theme: theme)
                         MetricPickerRow(title: "Row 6", position: .bottomLeft, config: $draftConfig, theme: theme)
                     }
                     HStack(spacing: 12) {
                         MetricPickerRow(title: "Row 7", position: .bottomCenter, config: $draftConfig, theme: theme)
                         MetricPickerRow(title: "Row 8", position: .bottomRight, config: $draftConfig, theme: theme)
                     }
                case .standard:
                    HStack(spacing: 12) {
                        MetricPickerRow(title: "Top Left", position: .topLeft, config: $draftConfig, theme: theme)
                        MetricPickerRow(title: "Top Right", position: .topRight, config: $draftConfig, theme: theme)
                    }
                    MetricPickerRow(title: "Center", position: .center, config: $draftConfig, theme: theme)
                    HStack(spacing: 12) {
                        MetricPickerRow(title: "Bottom Left", position: .bottomLeft, config: $draftConfig, theme: theme)
                        MetricPickerRow(title: "Bottom Right", position: .bottomRight, config: $draftConfig, theme: theme)
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: DesignSystem.radiusM).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
            .onChange(of: draftConfig.layoutStyle) { oldValue, newValue in
                if newValue == .minimal && draftConfig.metrics[.center] == nil {
                    draftConfig.metrics[.center] = .temperature
                }
            }
        }
    }

    @ViewBuilder
    func appearanceSection(theme: WeatherTheme) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingM) {
            StudioHeader(title: "APPEARANCE", icon: "paintbrush.fill", theme: theme)

             // Background Style
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(WidgetBackgroundStyle.allCases) { style in
                        Button {
                            HapticsManager.shared.impact(style: .light)
                            withAnimation { draftConfig.backgroundStyle = style }
                        } label: {
                            Text(style.displayName)
                                .font(.caption.weight(.medium))
                                .foregroundColor(draftConfig.backgroundStyle == style ? .white : theme.textColor)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(
                                    Capsule()
                                        .fill(draftConfig.backgroundStyle == style ? Color.blue : Color.white.opacity(0.2))
                                )
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)

            if draftConfig.backgroundStyle == .solid || draftConfig.backgroundStyle == .gradient {
                 // Color Picker
                 ScrollView(.horizontal, showsIndicators: false) {
                     HStack(spacing: 12) {
                         ForEach([Color.blue, .red, .orange, .purple, .black, .gray, .green, .mint, .indigo], id: \.self) { color in
                             colorButton(color, theme: theme)
                         }
                     }
                     .padding(.horizontal, 16)
                     .padding(.vertical, 8)
                 }
                 .padding(.horizontal, -16)
            }

            // Font Style
            VStack(alignment: .leading, spacing: 8) {
                Text("Typography")
                    .font(.caption)
                    .foregroundColor(theme.textColor.opacity(0.6))
                    .padding(.leading, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(WidgetFontStyle.allCases) { style in
                            Button {
                                draftConfig.fontStyle = style
                            } label: {
                                    Text(style.displayName)
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(draftConfig.fontStyle == style ? .white : theme.textColor)
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 12)
                                        .background(
                                            Capsule()
                                                .fill(draftConfig.fontStyle == style ? Color.blue : Color.white.opacity(0.2))
                                        )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.horizontal, -16)
            }

            // Icon Style picker removed as per user request to match app settings automatically
            .onAppear {
                // Sync with global app preference
                if viewModel.useMinimalistIcons {
                    draftConfig.iconStyle = .minimalist
                } else {
                    draftConfig.iconStyle = .realistic
                }
            }
        }
    }

    @ViewBuilder
    func optionsSection(theme: WeatherTheme) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingM) {
            StudioHeader(title: "OPTIONS", icon: "slider.horizontal.3", theme: theme)

            VStack(spacing: DesignSystem.spacingS) {
                // Border option is now always visible as per user request
                SettingsToggleRow(title: "Show Border", icon: "square", color: .indigo, textColor: theme.textColor, isOn: $draftConfig.showBorder)
            }
        }
    }

    @ViewBuilder
    func resetButton(theme: WeatherTheme) -> some View {
        Button {
            showResetAlert = true
        } label: {
            HStack {
                Image(systemName: "arrow.counterclockwise")
                Text("Reset to Defaults")
            }
            .font(.subheadline.weight(.medium))
            .foregroundColor(.red.opacity(0.8))
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.radiusM)
                    .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
            )
        }
        .padding(.bottom, 40)
        .alert("Reset Widget?", isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                withAnimation {
                    draftConfig = CustomWidgetConfiguration.default
                    draftConfig.widgetSize = .small
                }
            }
        } message: {
            Text("Are you sure you want to reset all widget customization settings to their defaults?")
        }
    }

    // MARK: - Components

    // Using locally defined MetricPickerRow tailored for this view
    struct MetricPickerRow: View {
        let title: String
        let position: WidgetMetricPosition
        @Binding var config: CustomWidgetConfiguration
        let theme: WeatherTheme

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(theme.textColor.opacity(0.6))
                    .padding(.leading, 2)

                Menu {
                    Button("None") {
                        config.metrics[position] = nil
                    }

                    ForEach(WidgetMetricType.allCases) { type in
                        Button {
                            config.metrics[position] = type
                        } label: {
                            Label(type.displayName, systemImage: type.icon)
                        }
                    }
                } label: {
                    HStack {
                        if let type = config.metrics[position] {
                            Image(systemName: type.icon)
                                .font(.caption)
                            Text(type.displayName)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        } else {
                            Text("Empty")
                                .font(.caption)
                                .foregroundColor(theme.textColor.opacity(0.5))
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundColor(theme.textColor.opacity(0.4))
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.2)))
                    .foregroundColor(theme.textColor)
                }
            }
        }
    }

    func colorButton(_ color: Color, theme: WeatherTheme) -> some View {
        Circle()
            .fill(color)
            .frame(width: 32, height: 32)
            .overlay(
                 Circle().stroke(Color.white, lineWidth: 2)
            )
            .shadow(radius: 2)
            .onTapGesture {
                HapticsManager.shared.impact(style: .light)
                withAnimation {
                    // Smart Switch logic
                    if draftConfig.backgroundStyle != .gradient && draftConfig.backgroundStyle != .solid {
                        draftConfig.backgroundStyle = .solid
                    }

                    if draftConfig.backgroundStyle == .gradient {
                        let colors = gradientColors(for: color)
                        draftConfig.customColors = colors.map { CustomColor(color: $0) }
                    } else {
                        draftConfig.customColors = [CustomColor(color: color)]
                    }
                }
            }
    }

    func gradientColors(for color: Color) -> [Color] {
        switch color {
        case .blue: return [.blue, .cyan]
        case .red: return [.red, .orange]
        case .orange: return [.orange, .yellow]
        case .purple: return [.purple, .pink]
        case .black: return [.black, Color(white: 0.2)]
        case .gray: return [.gray, .white]
        case .green: return [.green, .mint]
        case .mint: return [.mint, .teal]
        case .indigo: return [.indigo, .purple]
        default: return [color, color.opacity(0.6)]
        }
    }
}
