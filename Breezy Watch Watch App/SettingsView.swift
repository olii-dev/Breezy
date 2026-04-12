import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: WatchWeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            let theme = viewModel.currentTheme(isSystemDark: colorScheme == .dark)
            LinearGradient(
                gradient: Gradient(colors: [theme.topColor, theme.bottomColor]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16))
                            .foregroundColor(theme.textColor.opacity(0.8))
                        Text("Settings")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(theme.textColor)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)

                    SettingsCard(title: "CUSTOMIZE", textColor: theme.textColor) {
                        VStack(spacing: 4) {
                            SettingsDestinationRow(
                                icon: "paintpalette.fill",
                                title: "Appearance",
                                subtitle: appearanceSummary,
                                textColor: theme.textColor,
                                destination: AppearanceSettingsView().environmentObject(viewModel)
                            )

                            Divider().background(theme.textColor.opacity(0.2))

                            SettingsDestinationRow(
                                icon: "textformat.size",
                                title: "Display & Layout",
                                subtitle: displaySummary,
                                textColor: theme.textColor,
                                destination: DisplaySettingsView().environmentObject(viewModel)
                            )

                            Divider().background(theme.textColor.opacity(0.2))

                            SettingsDestinationRow(
                                icon: "dial.medium.fill",
                                title: "Units & Data",
                                subtitle: dataSummary,
                                textColor: theme.textColor,
                                destination: DataSettingsView().environmentObject(viewModel)
                            )
                        }
                    }
                    
                    Button {
                        viewModel.playHaptic(.click)
                        Task { await viewModel.refresh() }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh")
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.7))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 4)
                    
                    Text("Breezy v1.0")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(theme.textColor.opacity(0.5))
                        .padding(.bottom, 8)
                }
                .padding()
            }
            .focusable()
        }
    }

    private var appearanceSummary: String {
        let themeSummary = viewModel.themeMode == .auto ? "Dynamic" : viewModel.selectedPresetThemeName
        return "\(viewModel.appearanceMode.rawValue) • \(themeSummary)"
    }

    private var displaySummary: String {
        return "Layout, day view, and metric visibility"
    }

    private var dataSummary: String {
        let unit = WatchTemperatureUnit.fromUserDefaults() == .fahrenheit ? "°F" : "°C"
        return "\(unit) • \(viewModel.visibleMetrics.count) metrics"
    }
}

// MARK: - Components

struct SettingsCard<Content: View>: View {
    let title: String
    let textColor: Color
    let content: Content
    
    init(title: String, textColor: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.textColor = textColor
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(textColor.opacity(0.6))
                .padding(.leading, 4)
            
            VStack {
                content
            }
            .padding(8) // Reduced padding for small screens
            .background(textColor.opacity(0.08))
            .cornerRadius(12)
        }
    }
}

struct UnitButton: View {
    let title: String
    let isSelected: Bool
    let textColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.8)
                .foregroundColor(isSelected ? textColor : textColor.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(isSelected ? textColor.opacity(0.2) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

struct SettingsDestinationRow<Destination: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let textColor: Color
    let destination: Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundColor(textColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundColor(textColor)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundColor(textColor.opacity(0.62))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(textColor.opacity(0.55))
            }
            .padding(.vertical, 6)
        }
    }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject var viewModel: WatchWeatherViewModel
    @AppStorage("Breezy.useMinimalistIcons") private var useMinimalistIcons: Bool = true
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let theme = viewModel.currentTheme(isSystemDark: colorScheme == .dark)

        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [theme.topColor, theme.bottomColor]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    SettingsCard(title: "MODE", textColor: theme.textColor) {
                        HStack(spacing: 0) {
                            ForEach(WatchWeatherViewModel.AppearanceMode.allCases) { mode in
                                Button {
                                    viewModel.playHaptic(.click)
                                    viewModel.updateAppearanceMode(mode)
                                } label: {
                                    Text(mode.rawValue)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .foregroundColor(viewModel.appearanceMode == mode ? theme.textColor : theme.textColor.opacity(0.6))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 32)
                                        .background(viewModel.appearanceMode == mode ? theme.textColor.opacity(0.2) : Color.clear)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(theme.textColor.opacity(0.05))
                        .cornerRadius(8)
                    }

                    SettingsCard(title: "THEME", textColor: theme.textColor) {
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                viewModel.playHaptic(.click)
                                viewModel.updateThemeMode(.auto)
                            } label: {
                                HStack {
                                    Image(systemName: "wand.and.stars")
                                        .foregroundColor(theme.textColor)
                                    Text("Dynamic")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundColor(theme.textColor)
                                    Spacer()
                                    if viewModel.themeMode == .auto {
                                        Image(systemName: "checkmark")
                                            .font(.caption)
                                            .foregroundColor(theme.textColor)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(viewModel.themeMode == .auto ? theme.textColor.opacity(0.15) : Color.clear)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(WatchWeatherTheme.presets) { preset in
                                        Button {
                                            viewModel.playHaptic(.click)
                                            viewModel.updateSelectedPreset(preset.name)
                                        } label: {
                                            let themeDetails = (viewModel.isDark || (viewModel.appearanceMode == .system && colorScheme == .dark)) ? preset.dark : preset.light
                                            Circle()
                                                .fill(LinearGradient(colors: [themeDetails.topColor, themeDetails.bottomColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                                                .frame(width: 38, height: 38)
                                                .overlay(
                                                    Circle()
                                                        .stroke(theme.textColor, lineWidth: viewModel.themeMode == .preset && viewModel.selectedPresetThemeName == preset.name ? 2 : 0)
                                                )
                                                .overlay(
                                                    viewModel.themeMode == .preset && viewModel.selectedPresetThemeName == preset.name ?
                                                    Image(systemName: "checkmark").font(.caption2).fontWeight(.bold).foregroundColor(themeDetails.textColor) : nil
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
}
                            .padding(.horizontal, 2)
                             }
                         }
                        
                        NavigationLink(destination: WatchCustomThemeBuilderView().environmentObject(viewModel)) {
                            HStack {
                                Image(systemName: "paintbrush.fill")
                                    .foregroundColor(theme.textColor)
                                Text("Custom Theme Builder")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(theme.textColor)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(theme.textColor.opacity(0.5))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                     }

                    SettingsCard(title: "ICONS", textColor: theme.textColor) {
                        HStack(spacing: 8) {
                            Button {
                                useMinimalistIcons = true
                                viewModel.playHaptic(.click)
                                notifyIconChange()
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "cloud.sun.fill")
                                        .symbolRenderingMode(.multicolor)
                                    Text("Minimal")
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .foregroundColor(theme.textColor)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(useMinimalistIcons ? theme.textColor.opacity(0.15) : Color.clear)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)

                            Button {
                                useMinimalistIcons = false
                                viewModel.playHaptic(.click)
                                notifyIconChange()
                            } label: {
                                VStack(spacing: 4) {
                                    Text("⛅️")
                                    Text("Emoji")
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .foregroundColor(theme.textColor)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(!useMinimalistIcons ? theme.textColor.opacity(0.15) : Color.clear)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    SettingsCard(title: "TYPE", textColor: theme.textColor) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(WeatherFont.allCases) { font in
                                    Button {
                                        viewModel.playHaptic(.click)
                                        viewModel.typography = font
                                        if let defaults = UserDefaults(suiteName: WatchAppStorageKey.appGroup) {
                                            defaults.set(font.rawValue, forKey: "Breezy.typography")
                                        }
                                    } label: {
                                        Text("Aa")
                                            .font(.system(size: 16, weight: .bold))
                                            .fontDesign(font.design)
                                            .frame(width: 40, height: 40)
                                            .background(viewModel.typography == font ? theme.textColor.opacity(0.2) : theme.textColor.opacity(0.05))
                                            .cornerRadius(20)
                                            .foregroundColor(theme.textColor)
                                            .overlay(Circle().stroke(theme.textColor.opacity(0.3), lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Appearance")
    }

    private func notifyIconChange() {
        NotificationCenter.default.post(name: NSNotification.Name("WatchIconPreferenceChanged"), object: nil)
        Task { await viewModel.refresh() }
    }
}

struct DisplaySettingsView: View {
    @EnvironmentObject var viewModel: WatchWeatherViewModel
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let theme = viewModel.currentTheme(isSystemDark: colorScheme == .dark)

        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [theme.topColor, theme.bottomColor]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    SettingsCard(title: "LAYOUT", textColor: theme.textColor) {
                        VStack(spacing: 4) {
                            SettingsDestinationRow(
                                icon: "rectangle.grid.1x2.fill",
                                title: "Home Layout",
                                subtitle: "Reorder hourly and metrics",
                                textColor: theme.textColor,
                                destination: LayoutEditorView(viewModel: viewModel)
                            )

                            Divider().background(theme.textColor.opacity(0.2))

                            SettingsDestinationRow(
                                icon: "switch.2",
                                title: "Day View",
                                subtitle: "Metrics and sun schedule",
                                textColor: theme.textColor,
                                destination: WatchDisplayOptionsView().environmentObject(viewModel)
                            )

                            Divider().background(theme.textColor.opacity(0.2))

                            SettingsDestinationRow(
                                icon: "list.bullet.rectangle.portrait.fill",
                                title: "Metric Grid",
                                subtitle: "Choose what appears on the main screen",
                                textColor: theme.textColor,
                                destination: WatchMetricsEditorView(viewModel: viewModel)
                            )
                            
                            Divider().background(theme.textColor.opacity(0.2))

                            SettingsDestinationRow(
                                icon: "chart.bar.fill",
                                title: "Charts",
                                subtitle: "Toggle chart sections on/off",
                                textColor: theme.textColor,
                                destination: WatchChartsSettingsView().environmentObject(viewModel)
                            )
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Display")
    }
}

struct DataSettingsView: View {
    @EnvironmentObject var viewModel: WatchWeatherViewModel
    @State private var temperatureUnit: WatchTemperatureUnit = .celsius
    @State private var windSpeedUnit: WindSpeedUnit = .metersPerSecond
    @State private var pressureUnit: PressureUnit = .hectopascals
    @State private var visibilityUnit: VisibilityUnit = .kilometers
    @State private var precipitationUnit: PrecipitationUnit = .millimeters
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let theme = viewModel.currentTheme(isSystemDark: colorScheme == .dark)

        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [theme.topColor, theme.bottomColor]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    SettingsCard(title: "UNITS", textColor: theme.textColor) {
                        VStack(spacing: 4) {
                            SettingsDestinationRow(
                                icon: "thermometer",
                                title: "Temperature",
                                subtitle: temperatureUnit.rawValue.capitalized,
                                textColor: theme.textColor,
                                destination: EnumSelectionView(
                                    title: "Temperature",
                                    options: Array(WatchTemperatureUnit.allCases),
                                    selected: $temperatureUnit,
                                    textColor: theme.textColor,
                                    label: { $0.rawValue.capitalized },
                                    onSelect: updateTemperatureUnit
                                )
                            )

                            Divider().background(theme.textColor.opacity(0.2))

                            SettingsDestinationRow(
                                icon: "wind",
                                title: "Wind Speed",
                                subtitle: windSpeedUnit.displayName,
                                textColor: theme.textColor,
                                destination: EnumSelectionView(
                                    title: "Wind Speed",
                                    options: Array(WindSpeedUnit.allCases),
                                    selected: $windSpeedUnit,
                                    textColor: theme.textColor,
                                    label: { $0.displayName },
                                    onSelect: updateWindSpeedUnit
                                )
                            )

                            Divider().background(theme.textColor.opacity(0.2))

                            SettingsDestinationRow(
                                icon: "gauge.medium",
                                title: "Pressure",
                                subtitle: pressureUnit.displayName,
                                textColor: theme.textColor,
                                destination: EnumSelectionView(
                                    title: "Pressure",
                                    options: Array(PressureUnit.allCases),
                                    selected: $pressureUnit,
                                    textColor: theme.textColor,
                                    label: { $0.displayName },
                                    onSelect: updatePressureUnit
                                )
                            )

                            Divider().background(theme.textColor.opacity(0.2))

                            SettingsDestinationRow(
                                icon: "eye.fill",
                                title: "Visibility",
                                subtitle: visibilityUnit.rawValue,
                                textColor: theme.textColor,
                                destination: EnumSelectionView(
                                    title: "Visibility",
                                    options: Array(VisibilityUnit.allCases),
                                    selected: $visibilityUnit,
                                    textColor: theme.textColor,
                                    label: { $0.rawValue },
                                    onSelect: updateVisibilityUnit
                                )
                            )

                            Divider().background(theme.textColor.opacity(0.2))

                            SettingsDestinationRow(
                                icon: "cloud.rain.fill",
                                title: "Precipitation",
                                subtitle: precipitationUnit.rawValue,
                                textColor: theme.textColor,
                                destination: EnumSelectionView(
                                    title: "Precipitation",
                                    options: Array(PrecipitationUnit.allCases),
                                    selected: $precipitationUnit,
                                    textColor: theme.textColor,
                                    label: { $0.rawValue },
                                    onSelect: updatePrecipitationUnit
                                )
                            )
                        }
                    }

                    SettingsCard(title: "DATA", textColor: theme.textColor) {
                        Button {
                            viewModel.playHaptic(.success)
                            viewModel.clearCachedWeather()
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                    .foregroundColor(.red.opacity(0.9))
                                Text("Clear Cached Weather")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(theme.textColor)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Units & Data")
        .onAppear {
            let defaults = UserDefaults(suiteName: WatchAppStorageKey.appGroup)
            temperatureUnit = defaults?.string(forKey: WatchAppStorageKey.temperatureUnit).flatMap(WatchTemperatureUnit.init(rawValue:)) ?? .celsius
            windSpeedUnit = defaults?.string(forKey: WatchAppStorageKey.windSpeedUnit).flatMap(WindSpeedUnit.init(rawValue:)) ?? .metersPerSecond
            pressureUnit = defaults?.string(forKey: WatchAppStorageKey.pressureUnit).flatMap(PressureUnit.init(rawValue:)) ?? .hectopascals
            visibilityUnit = defaults?.string(forKey: WatchAppStorageKey.visibilityUnit).flatMap(VisibilityUnit.init(rawValue:)) ?? .kilometers
            precipitationUnit = defaults?.string(forKey: "Breezy.precipitationUnit").flatMap(PrecipitationUnit.init(rawValue:)) ?? .millimeters
        }
    }

    private func updateTemperatureUnit(_ unit: WatchTemperatureUnit) {
        temperatureUnit = unit
        viewModel.playHaptic(.click)
        if let defaults = UserDefaults(suiteName: WatchAppStorageKey.appGroup) {
            defaults.set(unit.rawValue, forKey: WatchAppStorageKey.temperatureUnit)
            defaults.synchronize()
        }
        NotificationCenter.default.post(name: NSNotification.Name("WatchTemperatureUnitChanged"), object: nil)
        Task { await viewModel.refresh() }
    }

    private func updateWindSpeedUnit(_ unit: WindSpeedUnit) {
        windSpeedUnit = unit
        persistAndRefresh(unit.rawValue, forKey: WatchAppStorageKey.windSpeedUnit)
    }

    private func updatePressureUnit(_ unit: PressureUnit) {
        pressureUnit = unit
        persistAndRefresh(unit.rawValue, forKey: WatchAppStorageKey.pressureUnit)
    }

    private func updateVisibilityUnit(_ unit: VisibilityUnit) {
        visibilityUnit = unit
        persistAndRefresh(unit.rawValue, forKey: WatchAppStorageKey.visibilityUnit)
    }

    private func updatePrecipitationUnit(_ unit: PrecipitationUnit) {
        precipitationUnit = unit
        persistAndRefresh(unit.rawValue, forKey: "Breezy.precipitationUnit")
    }

    private func persistAndRefresh(_ value: String, forKey key: String) {
        viewModel.playHaptic(.click)
        if let defaults = UserDefaults(suiteName: WatchAppStorageKey.appGroup) {
            defaults.set(value, forKey: key)
            defaults.synchronize()
        }
        NotificationCenter.default.post(name: NSNotification.Name("WatchContextUpdated"), object: nil)
        Task { await viewModel.refresh() }
    }
}

struct EnumSelectionView<Option: Hashable & Identifiable>: View {
    let title: String
    let options: [Option]
    @Binding var selected: Option
    let textColor: Color
    let label: (Option) -> String
    let onSelect: (Option) -> Void

    var body: some View {
        List {
            ForEach(options) { option in
                Button {
                    selected = option
                    onSelect(option)
                } label: {
                    HStack {
                        Text(label(option))
                            .foregroundColor(textColor)
                        Spacer()
                        if option == selected {
                            Image(systemName: "checkmark")
                                .foregroundColor(textColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(title)
    }
}

struct WatchMetricsEditorView: View {
    @ObservedObject var viewModel: WatchWeatherViewModel
    
    var body: some View {
        List {
            Section(header: Text("VISIBLE METRICS").font(.caption2)) {
                ForEach(WeatherMetric.allCases) { metric in
                    Toggle(isOn: Binding<Bool>(
                        get: { viewModel.visibleMetrics.contains(metric) },
                        set: { isOn in
                            viewModel.toggleMetric(metric, isEnabled: isOn)
                        }
                    )) {
                        HStack {
                            Image(systemName: metric.icon)
                                .frame(width: 18)
                            Text(metric.rawValue)
                                .font(.caption)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
            }
        }
    }
}

struct WatchDisplayOptionsView: View {
    @AppStorage(WatchAppStorageKey.showDayMetrics, store: UserDefaults(suiteName: WatchAppStorageKey.appGroup)) private var showDayMetrics = true
    @AppStorage(WatchAppStorageKey.showDaySunSchedule, store: UserDefaults(suiteName: WatchAppStorageKey.appGroup)) private var showDaySunSchedule = true
    @EnvironmentObject var viewModel: WatchWeatherViewModel

    var body: some View {
        List {
            Section("DAY VIEW") {
                Toggle("Detailed Metrics", isOn: binding(for: $showDayMetrics))
                Toggle("Sun Schedule", isOn: binding(for: $showDaySunSchedule))
            }
        }
        .navigationTitle("Display")
    }

    private func binding(for value: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue },
            set: { newValue in
                value.wrappedValue = newValue
                viewModel.playHaptic(.click)
            }
        )
    }
}

struct LayoutEditorView: View {
    @ObservedObject var viewModel: WatchWeatherViewModel
    
    var body: some View {
        List {
            Section(header: Text("MAIN LAYOUT").font(.caption2), footer: Text("Tap arrows to reorder.")) {
                ForEach(Array(viewModel.layoutSections.enumerated()), id: \.element.id) { index, section in
                    HStack {
                        Image(systemName: section.icon)
                            .frame(width: 16) // Slightly smaller icon
                            .foregroundColor(.gray)
                        Text(section.rawValue)
                            .font(.system(size: 14))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6) // Allow significant scaling
                        Spacer()
                        
                        // Up Button
                        if index > 0 {
                            Button {
                                withAnimation {
                                    viewModel.layoutSections.move(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
                                }
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .frame(width: 24, height: 24)
                            .background(Color.gray.opacity(0.2))
                            .clipShape(Circle())
                        } else {
                            Spacer().frame(width: 24)
                        }
                        
                        // Down Button
                        if index < viewModel.layoutSections.count - 1 {
                            Button {
                                withAnimation {
                                    viewModel.layoutSections.move(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
                                }
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .frame(width: 24, height: 24)
                            .background(Color.gray.opacity(0.2))
                            .clipShape(Circle())
                        } else {
                            Spacer().frame(width: 24)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            
            Section {
                Button("Reset Layout") {
                    viewModel.playHaptic(.success)
                    viewModel.resetLayout()
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Layout")
    }
}

struct WatchChartsSettingsView: View {
    @AppStorage("Breezy.watch.chartTemperature") private var showTemperature = true
    @AppStorage("Breezy.watch.chartUV") private var showUV = true
    @AppStorage("Breezy.watch.chartWind") private var showWind = true
    @AppStorage("Breezy.watch.chartHumidity") private var showHumidity = true
    @EnvironmentObject var viewModel: WatchWeatherViewModel
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let theme = viewModel.currentTheme(isSystemDark: colorScheme == .dark)

        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [theme.topColor, theme.bottomColor]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    SettingsCard(title: "CHART SECTIONS", textColor: theme.textColor) {
                        VStack(spacing: 6) {
                            chartToggle(icon: "thermometer.medium", title: "Temperature", isOn: $showTemperature)
                            Divider().background(theme.textColor.opacity(0.2))
                            chartToggle(icon: "sun.max.fill", title: "UV Index", isOn: $showUV)
                            Divider().background(theme.textColor.opacity(0.2))
                            chartToggle(icon: "wind", title: "Wind", isOn: $showWind)
                            Divider().background(theme.textColor.opacity(0.2))
                            chartToggle(icon: "humidity.fill", title: "Humidity & Cloud", isOn: $showHumidity)
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Charts")
    }

    private func chartToggle(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(theme(for: colorScheme).textColor)
            Toggle(title, isOn: isOn)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(theme(for: colorScheme).textColor)
        }
        .padding(.vertical, 2)
    }

    private func theme(for colorScheme: ColorScheme) -> WatchWeatherTheme {
        viewModel.currentTheme(isSystemDark: colorScheme == .dark)
    }
}
