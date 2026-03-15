import SwiftUI

struct ThemeGalleryView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        ZStack {
            // Background matches current theme or app default
            let theme = viewModel.currentTheme(colorScheme: colorScheme)
            AnimatedGradientBackground(colors: [theme.topColor, theme.bottomColor])
            
            ScrollView {
                VStack(spacing: 32) {
                    
                    // Header
                    VStack(spacing: 8) {
                        Text("Themes")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(theme.textColor)
                        
                        Text("Choose a style or create your own")
                            .font(.subheadline)
                            .foregroundColor(theme.textColor.opacity(0.7))
                    }
                    .padding(.top, 20)
                    
                    // Auto Mode Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("DYNAMIC")
                            .font(.caption.weight(.bold))
                            .foregroundColor(theme.textColor.opacity(0.6))
                            .padding(.leading, 8)
                        
                        Button {
                            HapticsManager.shared.impact(style: .light)
                            withAnimation {
                                viewModel.themeMode = .auto
                            }
                        } label: {
                            HStack(spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 48, height: 48)
                                    Image(systemName: "cloud.sun.fill")
                                        .foregroundColor(.white)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Weather Mode")
                                        .font(.headline)
                                        .foregroundColor(theme.textColor)
                                    Text("Background changes with the weather")
                                        .font(.caption)
                                        .foregroundColor(theme.textColor.opacity(0.7))
                                }
                                Spacer()
                                
                                if viewModel.themeMode == .auto {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.title3)
                                }
                            }
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial.opacity(viewModel.glassOpacity)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(viewModel.themeMode == .auto ? Color.blue : Color.clear, lineWidth: 2)
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    // Presets
                    VStack(alignment: .leading, spacing: 16) {
                        Text("PRESETS")
                            .font(.caption.weight(.bold))
                            .foregroundColor(theme.textColor.opacity(0.6))
                            .padding(.leading, 8)
                        
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(WeatherTheme.presets, id: \.name) { preset in
                                let isDark: Bool = {
                                    switch viewModel.appearanceMode {
                                    case .light: return false
                                    case .dark: return true
                                    case .auto: return colorScheme == .dark
                                    }
                                }()
                                
                                ThemeCard(
                                    name: preset.name,
                                    theme: isDark ? preset.dark : preset.light,
                                    isSelected: viewModel.themeMode == .preset && viewModel.selectedPresetThemeName == preset.name
                                ) {
                                    withAnimation {
                                        viewModel.selectedPresetThemeName = preset.name
                                        viewModel.themeMode = .preset
                                    }
                                }
                            }
                            
                            // Custom Theme Card
                            NavigationLink {
                                CustomThemeBuilderView(viewModel: viewModel)
                            } label: {
                                CustomThemeCard(
                                    isSelected: viewModel.themeMode == .custom,
                                    customTheme: viewModel.customTheme
                                )
                            }
                            .simultaneousGesture(TapGesture().onEnded {
                                HapticsManager.shared.impact(style: .light)
                            })
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 40)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(viewModel.currentTheme(colorScheme: colorScheme).isDark ? .dark : .light, for: .navigationBar)
    }
}

struct ThemeCard: View {
    let name: String
    let theme: WeatherTheme
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticsManager.shared.impact(style: .light)
            action()
        }) {
             VStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [theme.topColor, theme.bottomColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.white : Color.white.opacity(0.2), lineWidth: isSelected ? 3 : 1)
                    )
                    .shadow(color: theme.topColor.opacity(0.3), radius: 8, x: 0, y: 4)
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.white)
                                .font(.title3)
                                .padding(8)
                                .background(Circle().fill(Color.black.opacity(0.2)).blur(radius: 2))
                        }
                    }
                
                Text(name)
                    .font(.subheadline.weight(.medium))
//                    .foregroundColor(.white) // Using parent context
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct CustomThemeCard: View {
    let isSelected: Bool
    let customTheme: WeatherTheme
    
    var body: some View {
        VStack(alignment: .leading) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [customTheme.topColor, customTheme.bottomColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 100)
                
                VStack {
                    Image(systemName: "plus")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                    Text("Custom")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.white : Color.white.opacity(0.2), lineWidth: isSelected ? 3 : 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                        .font(.title3)
                        .padding(8)
                        .background(Circle().fill(Color.black.opacity(0.2)).blur(radius: 2))
                }
            }
            
            Text("Create Custom")
                .font(.subheadline.weight(.medium))
        }
    }
}
