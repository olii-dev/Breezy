import SwiftUI

struct CustomThemeBuilderView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @State private var topColor: Color = .blue
    @State private var bottomColor: Color = .purple
    @State private var textColor: Color = .white
    
    init(viewModel: WeatherViewModel) {
        self.viewModel = viewModel
        // Initialize state from existing custom theme
        _topColor = State(initialValue: viewModel.customTheme.topColor)
        _bottomColor = State(initialValue: viewModel.customTheme.bottomColor)
        _textColor = State(initialValue: viewModel.customTheme.textColor)
    }
    
    var body: some View {
        ZStack {
            // Live Background Preview
            AnimatedGradientBackground(colors: [topColor, bottomColor])
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 32) {
                    
                    // Preview Card
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
                            RoundedRectangle(cornerRadius: 24)
                                .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24)
                                        .stroke(textColor.opacity(0.2), lineWidth: 1)
                                )
                        )
                        .shadow(color: .black.opacity(0.1), radius: 10)
                    }
                    .padding(.top, 20)
                    
                    // Controls
                    VStack(spacing: 24) {
                        ColorPickerRow(title: "Top Gradient", color: $topColor, textColor: textColor)
                            .onChange(of: topColor) { _, _ in
                                HapticsManager.shared.impact(style: .light)
                            }
                        ColorPickerRow(title: "Bottom Gradient", color: $bottomColor, textColor: textColor)
                            .onChange(of: bottomColor) { _, _ in
                                HapticsManager.shared.impact(style: .light)
                            }
                        ColorPickerRow(title: "Text Color", color: $textColor, textColor: textColor)
                            .onChange(of: textColor) { _, _ in
                                HapticsManager.shared.impact(style: .light)
                            }
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
                    )
                    .padding(.horizontal)
                    
                    // Action Buttons
                    VStack(spacing: 16) {
                        Button {
                            // Apply and Save
                            HapticsManager.shared.notification(type: .success)
                            let newTheme = WeatherTheme(topColor: topColor, bottomColor: bottomColor, textColor: textColor)
                            viewModel.customTheme = newTheme
                            viewModel.themeMode = .custom
                            dismiss()
                        } label: {
                            Text("Save & Apply Theme")
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
        // Dynamically determining isDark for the PREVIEW colors, not just the saved theme
        .toolbarColorScheme(WeatherTheme(topColor: topColor, bottomColor: bottomColor, textColor: textColor).isDark ? .dark : .light, for: .navigationBar)
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
                .foregroundColor(textColor) // Use preview text color so labels are visible on background
            Spacer()
            ColorPicker("", selection: $color, supportsOpacity: false)
                .labelsHidden()
        }
    }
}
