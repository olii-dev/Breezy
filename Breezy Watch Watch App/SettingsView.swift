import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: WatchWeatherViewModel
    @State private var temperatureUnit: String = "celsius"
    @AppStorage("Breezy.useMinimalistIcons") private var useMinimalistIcons: Bool = true
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ZStack {
            // Background
            let theme = viewModel.currentTheme(isSystemDark: colorScheme == .dark)
            LinearGradient(
                gradient: Gradient(colors: [theme.topColor, theme.bottomColor]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    
                    // Header
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
                    
                    // 1. Appearance Section
                    SettingsCard(title: "APPEARANCE", textColor: theme.textColor) {
                        VStack(spacing: 12) {
                            // Mode Selector
                            HStack(spacing: 0) {
                                ForEach(WatchWeatherViewModel.AppearanceMode.allCases) { mode in
                                    Button {
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
                            
                            Divider().background(theme.textColor.opacity(0.2))
                            
                            // Dynamic / Presets
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    viewModel.updateThemeMode(.auto)
                                } label: {
                                    HStack {
                                        Image(systemName: "wand.and.stars")
                                            .foregroundColor(theme.textColor)
                                        Text("Dynamic")
                                            .font(.system(size: 13, weight: .medium, design: .rounded))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
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
                                                viewModel.updateSelectedPreset(preset.name)
                                            } label: {
                                                let themeDetails = (viewModel.isDark || (viewModel.appearanceMode == .system && colorScheme == .dark)) ? preset.dark : preset.light
                                                Circle()
                                                    .fill(LinearGradient(colors: [themeDetails.topColor, themeDetails.bottomColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                                                    .frame(width: 34, height: 34)
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
                        }
                    }
                    
                    // 2. Display Section
                    SettingsCard(title: "DISPLAY", textColor: theme.textColor) {
                        VStack(spacing: 12) {
                            // Icon Style
                            HStack(spacing: 8) {
                                Button {
                                    useMinimalistIcons = true
                                    notifyIconChange()
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: "cloud.sun.fill").symbolRenderingMode(.multicolor)
                                        Text("Minimal")
                                            .font(.caption2)
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
                            
                            Divider().background(theme.textColor.opacity(0.2))
                            
                            // Typography
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(WeatherFont.allCases) { font in
                                        Button {
                                            viewModel.typography = font
                                            if let defaults = UserDefaults(suiteName: "group.com.breezy.weather") {
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
                                                .overlay(
                                                    Circle().stroke(theme.textColor.opacity(0.3), lineWidth: 1)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    
                    // 3. Units & Data
                    SettingsCard(title: "PREFERENCES", textColor: theme.textColor) {
                        VStack(spacing: 10) {
                            // Layout Editor
                            NavigationLink(destination: LayoutEditorView(viewModel: viewModel)) {
                                HStack {
                                    Image(systemName: "rectangle.grid.1x2.fill")
                                        .foregroundColor(theme.textColor)
                                    Text("Layout")
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .foregroundColor(theme.textColor)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundColor(theme.textColor.opacity(0.6))
                                }
                                .padding(.vertical, 4)
                            }
                            
                            Divider().background(theme.textColor.opacity(0.2))

                            // Temperature Unit
                            HStack(spacing: 0) {
                                UnitButton(title: "°C", isSelected: temperatureUnit == "celsius", textColor: theme.textColor) {
                                    updateUnit("celsius")
                                }
                                UnitButton(title: "°F", isSelected: temperatureUnit == "fahrenheit", textColor: theme.textColor) {
                                    updateUnit("fahrenheit")
                                }
                            }
                            .background(theme.textColor.opacity(0.05))
                            .cornerRadius(8)
                            
                            Divider().background(theme.textColor.opacity(0.2))
                            
                            // Metrics Link
                            NavigationLink(destination: WatchMetricsEditorView(viewModel: viewModel)) {
                                HStack {
                                    Image(systemName: "list.bullet.rectangle.portrait.fill")
                                        .foregroundColor(theme.textColor)
                                    Text("Grid")
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .foregroundColor(theme.textColor)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundColor(theme.textColor.opacity(0.6))
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    
                    // Refresh Action
                    Button {
                        Task { await viewModel.loadWeather() }
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
        .onAppear {
            loadTemperatureUnit()
        }
    }
    
    // MARK: - Helpers
    private func loadTemperatureUnit() {
        if let defaults = UserDefaults(suiteName: "group.com.breezy.weather"),
           let unit = defaults.string(forKey: "Breezy.temperatureUnit") {
            temperatureUnit = unit
        } else {
            temperatureUnit = "celsius"
        }
    }
    
    private func updateUnit(_ unit: String) {
        temperatureUnit = unit
        if let defaults = UserDefaults(suiteName: "group.com.breezy.weather") {
            defaults.set(unit, forKey: "Breezy.temperatureUnit")
            defaults.synchronize()
        }
        NotificationCenter.default.post(name: NSNotification.Name("WatchTemperatureUnitChanged"), object: nil)
        Task { await viewModel.loadWeather() }
    }
    
    private func notifyIconChange() {
        NotificationCenter.default.post(name: NSNotification.Name("WatchIconPreferenceChanged"), object: nil)
        Task { await viewModel.loadWeather() }
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

struct WatchMetricsEditorView: View {
    @ObservedObject var viewModel: WatchWeatherViewModel
    
    var body: some View {
        List {
            Section(header: Text("VISIBLE METRICS").font(.caption2)) {
                ForEach(WeatherMetric.allCases) { metric in
                    Toggle(isOn: Binding<Bool>(
                        get: { viewModel.visibleMetrics.contains(metric) },
                        set: { isOn in
                            if isOn {
                                viewModel.visibleMetrics.insert(metric)
                            } else {
                                viewModel.visibleMetrics.remove(metric)
                            }
                            if let defaults = UserDefaults(suiteName: "group.com.breezy.weather"),
                               let data = try? JSONEncoder().encode(viewModel.visibleMetrics) {
                                defaults.set(data, forKey: "Breezy.visibleMetrics")
                            }
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
                    viewModel.resetLayout()
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Layout")
    }
}
