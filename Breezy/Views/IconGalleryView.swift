#if os(iOS)
import SwiftUI

struct IconGalleryView: View {
    @ObservedObject var viewModel: WeatherViewModel
    @StateObject private var iconManager = IconManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        ZStack {
            // Background matches app theme
            let theme = viewModel.currentTheme(colorScheme: colorScheme)
            AnimatedGradientBackground(colors: [theme.topColor, theme.bottomColor])
            
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("App Icons")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(theme.textColor)
                        
                        Text("Customise your Breezy experience")
                            .font(.system(size: 16))
                            .foregroundColor(theme.textColor.opacity(0.7))
                    }
                    .padding(.top, 20)
                    
                    // Icon Grid
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(IconManager.AppIcon.allCases, id: \.self) { icon in
                            IconCard(
                                icon: icon,
                                isSelected: iconManager.currentIcon == icon,
                                textColor: theme.textColor
                            ) {
                                HapticsManager.shared.impact(style: .light)
                                Task { @MainActor in
                                    await iconManager.setIcon(icon)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 40)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(viewModel.currentTheme(colorScheme: colorScheme).isDark ? .dark : .light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(viewModel.currentTheme(colorScheme: colorScheme).textColor.opacity(0.7))
                }
            }
        }
    }
}

struct IconCard: View {
    let icon: IconManager.AppIcon
    let isSelected: Bool
    let textColor: Color
    let action: () -> Void
    
    var body: some View {
        Button {
            HapticsManager.shared.impact(style: .medium)
            action()
        } label: {
            VStack(spacing: 12) {
                // Icon preview with glassmorphic container
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(
                            isSelected ?
                                LinearGradient(colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                LinearGradient(colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 28)
                                .stroke(
                                    isSelected ? Color.blue.opacity(0.5) : Color.white.opacity(0.2),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: isSelected ? Color.blue.opacity(0.3) : Color.black.opacity(0.1), radius: isSelected ? 12 : 8, x: 0, y: 4)
                        .frame(height: 160)
                    
                    // Actual icon image
                    if let uiImage = UIImage(named: icon.previewImageName) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .cornerRadius(22)
                            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                    } else {
                        Image(systemName: icon.previewImage)
                            .font(.system(size: 50))
                            .foregroundColor(textColor)
                    }
                    
                    // Selected checkmark
                    if isSelected {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Color.blue, Color.white)
                                    .padding(12)
                            }
                            Spacer()
                        }
                    }
                }
                
                // Icon name
                Text(icon.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(textColor)
            }
        }
        .buttonStyle(PlainButtonStyle()) // Changed from PressedButtonStyle to PlainButtonStyle
        .contentShape(Rectangle())
    }
}

struct PressedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    NavigationView {
        IconGalleryView(viewModel: WeatherViewModel())
    }
}
#endif
