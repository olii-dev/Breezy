import SwiftUI

struct WatchCustomThemeBuilderView: View {
    @EnvironmentObject var viewModel: WatchWeatherViewModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    
    @State private var topColor = Color.blue
    @State private var bottomColor = Color.purple
    @State private var textColor = Color.white
    @State private var themeName = "My Theme"
    
    private let colorPalette: [(String, Color)] = [
        ("Sky", Color(red: 0.53, green: 0.73, blue: 0.95)),
        ("Ocean", Color(red: 0.13, green: 0.58, blue: 0.69)),
        ("Forest", Color(red: 0.44, green: 0.70, blue: 0.50)),
        ("Sunset", Color(red: 1.0, green: 0.32, blue: 0.18)),
        ("Rose", Color(red: 0.97, green: 0.77, blue: 0.85)),
        ("Lavender", Color(red: 0.83, green: 0.77, blue: 0.98)),
        ("Midnight", Color(red: 0.14, green: 0.15, blue: 0.25)),
        ("Mango", Color(red: 1.0, green: 0.89, blue: 0.35)),
        ("Berry", Color(red: 0.63, green: 0.22, blue: 0.42)),
        ("Arctic", Color(red: 0.85, green: 0.93, blue: 0.98)),
        ("Ember", Color(red: 0.85, green: 0.28, blue: 0.15)),
        ("Mint", Color(red: 0.62, green: 0.95, blue: 0.78))
    ]
    
    var body: some View {
        let theme = viewModel.currentTheme(isSystemDark: colorScheme == .dark)
        
        ZStack {
            LinearGradient(
                colors: [topColor, bottomColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 12) {
                    Text("CUSTOM THEME")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(textColor.opacity(0.6))
                    
                    previewCard
                    
                    colorSection(title: "Top Color", selection: $topColor)
                    colorSection(title: "Bottom Color", selection: $bottomColor)
                    
                    textColorSection
                    
                    Button {
                        saveTheme()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                            Text("Apply Theme")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(textColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(textColor.opacity(0.2))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .focusable()
        }
    }
    
    @ViewBuilder
    private var previewCard: some View {
        VStack(spacing: 8) {
            Text("Preview")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(textColor.opacity(0.6))
            
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(
                        colors: [topColor, bottomColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(textColor.opacity(0.2), lineWidth: 1)
                    )
                
                HStack(spacing: 10) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 22))
                        .foregroundColor(textColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("22°")
                            .font(.system(size: 20, weight: .thin))
                            .foregroundColor(textColor)
                        Text("Sunny")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(textColor.opacity(0.8))
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func colorSection(title: String, selection: Binding<Color>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(textColor.opacity(0.7))
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(colorPalette, id: \.0) { name, color in
                    Button {
                        selection.wrappedValue = color
                        viewModel.playHaptic(.click)
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: selection.wrappedValue == color ? 2 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(textColor.opacity(0.08))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private var textColorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Text Color")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(textColor.opacity(0.7))
            
            HStack(spacing: 12) {
                Button {
                    textColor = .white
                    viewModel.playHaptic(.click)
                } label: {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 32, height: 32)
                        .overlay(Circle().stroke(Color.gray, lineWidth: textColor == .white ? 2 : 0))
                }
                .buttonStyle(.plain)
                
                Button {
                    textColor = Color(red: 0.2, green: 0.2, blue: 0.25)
                    viewModel.playHaptic(.click)
                } label: {
                    Circle()
                        .fill(Color(red: 0.2, green: 0.2, blue: 0.25))
                        .frame(width: 32, height: 32)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1))
                        .overlay(
                            Circle()
                                .stroke(Color.blue, lineWidth: textColor == Color(red: 0.2, green: 0.2, blue: 0.25) ? 2 : 0)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(textColor.opacity(0.08))
        .cornerRadius(12)
    }
    
    private func saveTheme() {
        let defaults = UserDefaults(suiteName: "group.com.breezy.weather")
        
        defaults?.set(topColor.toHex(), forKey: "Breezy.customTheme.topColor")
        defaults?.set(bottomColor.toHex(), forKey: "Breezy.customTheme.bottomColor")
        defaults?.set(textColor.toHex(), forKey: "Breezy.customTheme.textColor")
        
        viewModel.updateThemeMode(.preset)
        viewModel.updateSelectedPreset("Custom")
        
        viewModel.playHaptic(.success)
    }
}

extension Color {
    func toHex() -> String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
