import SwiftUI

struct CustomThemeBuilderView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @State private var topColor: Color = .blue
    @State private var bottomColor: Color = .purple
    @State private var textColor: Color = .white
    @State private var themeName: String = ""
    @State private var glassStyle: GlassStyle = .ultraThin
    @State private var cornerRadius: CornerRadiusStyle = .medium
    @State private var shadowIntensity: ShadowIntensity = .medium
    @State private var borderStyle: BorderStyle = .subtle
    
    private var isEditing: Bool { editThemeID != nil }
    @State private var editThemeID: String? = nil
    
    init(viewModel: WeatherViewModel, editing themeID: String? = nil) {
        self.viewModel = viewModel
        self.editThemeID = themeID
        
        if let id = themeID, let theme = viewModel.customThemes.first(where: { $0.id == id }) {
            _topColor = State(initialValue: theme.topColor)
            _bottomColor = State(initialValue: theme.bottomColor)
            _textColor = State(initialValue: theme.textColor)
            _themeName = State(initialValue: theme.name)
            _glassStyle = State(initialValue: theme.glassStyle)
            _cornerRadius = State(initialValue: theme.cornerRadius)
            _shadowIntensity = State(initialValue: theme.shadowIntensity)
            _borderStyle = State(initialValue: theme.borderStyle)
        } else {
            _topColor = State(initialValue: viewModel.customTheme.topColor)
            _bottomColor = State(initialValue: viewModel.customTheme.bottomColor)
            _textColor = State(initialValue: viewModel.customTheme.textColor)
            _themeName = State(initialValue: "My Theme")
        }
    }
    
    var body: some View {
        ZStack {
            AnimatedGradientBackground(colors: [topColor, bottomColor])
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 32) {
                    
                    VStack(spacing: 16) {
                        Text("Preview")
                            .font(.headline)
                            .foregroundColor(textColor.opacity(0.8))
                        
                        VStack(spacing: 12) {
                            Text("San Francisco")
                                .font(.title2.weight(.medium))
                                .foregroundColor(textColor)
                            
                            Text("72°")
                                .font(.system(size: 64, weight: .thin))
                                .foregroundColor(textColor)
                            
                            HStack {
                                Image(systemName: "sun.max.fill")
                                Text("Sunny")
                            }
                            .font(.title3)
                            .foregroundColor(textColor.opacity(0.9))
                        }
                        .padding(32)
                        .background(
                            RoundedRectangle(cornerRadius: cornerRadiusValue)
                                .fill(.ultraThinMaterial.opacity(glassOpacityValue))
                                .overlay(
                                    RoundedRectangle(cornerRadius: cornerRadiusValue)
                                        .stroke(textColor.opacity(borderOpacity), lineWidth: borderWidth)
                                )
                        )
                        .shadow(color: .black.opacity(shadowOpacityValue), radius: shadowRadiusValue, y: 6)
                    }
                    .padding(.top, 20)
                    
                    VStack(spacing: 24) {
                        TextField("Theme Name", text: $themeName)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(textColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.ultraThinMaterial.opacity(0.15))
                            )
                        
                        Divider().overlay(textColor.opacity(0.15))
                        
                        ColorPickerRow(title: "Top Gradient", color: $topColor, textColor: textColor)
                            .onChange(of: topColor) { _, _ in HapticsManager.shared.impact(style: .light) }
                        ColorPickerRow(title: "Bottom Gradient", color: $bottomColor, textColor: textColor)
                            .onChange(of: bottomColor) { _, _ in HapticsManager.shared.impact(style: .light) }
                        ColorPickerRow(title: "Text Color", color: $textColor, textColor: textColor)
                            .onChange(of: textColor) { _, _ in HapticsManager.shared.impact(style: .light) }
                        
                        Divider().overlay(textColor.opacity(0.15))
                        
                        PickerRow(title: "Glass Style", selection: $glassStyle, textColor: textColor)
                        PickerRow(title: "Corner Radius", selection: $cornerRadius, textColor: textColor)
                        PickerRow(title: "Shadow", selection: $shadowIntensity, textColor: textColor)
                        PickerRow(title: "Border", selection: $borderStyle, textColor: textColor)
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
                    )
                    .padding(.horizontal)
                    
                    VStack(spacing: 16) {
                        Button {
                            HapticsManager.shared.notification(type: .success)
                            saveTheme()
                            viewModel.themeMode = .custom
                            dismiss()
                        } label: {
                            Text(isEditing ? "Update Theme" : "Save & Apply Theme")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(16)
                                .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)
                        }
                        
                        Button("Cancel") {
                            HapticsManager.shared.impact(style: .light)
                            dismiss()
                        }
                        .foregroundColor(textColor.opacity(0.7))
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(WeatherTheme(topColor: topColor, bottomColor: bottomColor, textColor: textColor).isDark ? .dark : .light, for: .navigationBar)
    }
    
    private func saveTheme() {
        let name = themeName.trimmingCharacters(in: .whitespaces).isEmpty ? "Custom" : themeName.trimmingCharacters(in: .whitespaces)
        
        if let id = editThemeID {
            if let index = viewModel.customThemes.firstIndex(where: { $0.id == id }) {
                var updated = WeatherTheme(id: id, name: name, topColor: topColor, bottomColor: bottomColor, textColor: textColor)
                updated.glassStyle = glassStyle
                updated.cornerRadius = cornerRadius
                updated.shadowIntensity = shadowIntensity
                updated.borderStyle = borderStyle
                viewModel.customThemes[index] = updated
                viewModel.selectedCustomThemeID = id
            }
        } else {
            let newTheme = WeatherTheme(name: name, topColor: topColor, bottomColor: bottomColor, textColor: textColor)
            var themeToSave = newTheme
            themeToSave.glassStyle = glassStyle
            themeToSave.cornerRadius = cornerRadius
            themeToSave.shadowIntensity = shadowIntensity
            themeToSave.borderStyle = borderStyle
            viewModel.customThemes.append(themeToSave)
            viewModel.selectedCustomThemeID = themeToSave.id
        }
    }
    
    private var glassOpacityValue: Double {
        switch glassStyle {
        case .ultraThin: return 0.15
        case .thin: return 0.25
        case .regular: return 0.4
        case .thick: return 0.6
        }
    }
    
    private var cornerRadiusValue: CGFloat {
        switch cornerRadius {
        case .small: return 8
        case .medium: return 16
        case .large: return 24
        }
    }
    
    private var shadowRadiusValue: CGFloat {
        switch shadowIntensity {
        case .subtle: return 4
        case .medium: return 10
        case .prominent: return 18
        }
    }
    
    private var shadowOpacityValue: Double {
        switch shadowIntensity {
        case .subtle: return 0.05
        case .medium: return 0.1
        case .prominent: return 0.2
        }
    }
    
    private var borderOpacity: Double {
        switch borderStyle {
        case .none: return 0
        case .subtle: return 0.15
        case .prominent: return 0.35
        }
    }
    
    private var borderWidth: CGFloat {
        switch borderStyle {
        case .none: return 0
        case .subtle: return 0.5
        case .prominent: return 1.5
        }
    }
}

struct ColorPickerRow: View {
    let title: String
    @Binding var color: Color
    let textColor: Color
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(textColor)
            Spacer()
            ColorPicker("", selection: $color, supportsOpacity: false)
                .labelsHidden()
        }
    }
}

struct PickerRow<T: RawRepresentable & CaseIterable & Hashable>: View where T.RawValue == String, T.AllCases: RandomAccessCollection {
    let title: String
    @Binding var selection: T
    let textColor: Color
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(textColor)
            Spacer()
            Picker("", selection: $selection) {
                ForEach(Array(T.allCases), id: \.rawValue) { option in
                    Text(option.rawValue.capitalized).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(textColor)
        }
    }
}
