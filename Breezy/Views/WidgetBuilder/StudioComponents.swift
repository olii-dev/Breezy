//
//  StudioComponents.swift
//  Breezy
//
//  Created for Design/Widget Studio
//

import SwiftUI

struct StudioHeader: View {
    let title: String
    let icon: String
    let theme: WeatherTheme
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundColor(theme.textColor.opacity(0.6))
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundColor(theme.textColor.opacity(0.6))
                .tracking(1)
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

struct SettingsToggleRow: View {
    let title: String
    let icon: String
    let color: Color
    let textColor: Color
    @Binding var isOn: Bool
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(textColor)
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(color)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial.opacity(0.4))
        )
    }
}
