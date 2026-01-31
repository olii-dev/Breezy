//
//  SettingsView.swift
//  BreezyWatch Watch App
//
//  Standalone settings for WatchOS
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: WatchWeatherViewModel
    @Environment(\.dismiss) var dismiss
    
    let themes = [
        "Cotton Candy", "Ocean", "Forest", "Sunset", 
        "Midnight", "Lavender", "Royal", "Mango"
    ]
    
    let fonts = ["System", "Rounded", "Serif", "Monospace"]
    
    var body: some View {
        Form {
            Section(header: Text("Appearance")) {
                Picker("Mode", selection: $viewModel.themeMode) {
                    Text("Weather").tag("Weather")
                    Text("Pro Theme").tag("Pro Theme")
                }
                .onChange(of: viewModel.themeMode) { newValue in
                    // Clear overrides when mode changes
                    viewModel.activeThemeColors = nil
                    UserDefaults.standard.removeObject(forKey: "Breezy.theme.top")
                }
                
                if viewModel.themeMode == "Pro Theme" {
                    Picker("Theme", selection: $viewModel.presetTheme) {
                        ForEach(themes, id: \.self) { theme in
                            Text(theme).tag(theme)
                        }
                    }
                    .onChange(of: viewModel.presetTheme) { newValue in
                        // Clear active overrides 
                        viewModel.activeThemeColors = nil 
                        UserDefaults.standard.removeObject(forKey: "Breezy.theme.top")
                    }
                }
                
                Toggle("Minimalist Icons", isOn: $viewModel.useMinimalistIcons)
                
                Picker("Font", selection: $viewModel.typography) {
                    ForEach(fonts, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }
            }
            
            Section(footer: Text("Breezy v1.0")) {
                Button("Done") {
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Settings")
    }
}
