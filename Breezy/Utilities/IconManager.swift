//
//  IconManager.swift
//  Breezy
//
//  App Icon Switching Manager
//

import UIKit
import Combine

class IconManager: ObservableObject {
    static let shared = IconManager()
    
    @Published var currentIcon: AppIcon
    
    private init() {
        // Initialize currentIcon based on system state
        if let iconName = UIApplication.shared.alternateIconName {
            self.currentIcon = AppIcon(rawValue: iconName) ?? .primary
        } else {
            self.currentIcon = .primary
        }
    }
    
    enum AppIcon: String, CaseIterable {
        case primary = "Default"
        case dark = "DarkIcon"
        case sunset = "SunsetIcon"
        case ocean = "OceanIcon"
        case minimalist = "MinimalistIcon"
        
    /*  
        case neon = "NeonIcon"
        case retro = "RetroIcon"
        case gold = "GoldIcon"
    */
        
        var displayName: String {
            switch self {
            case .primary: return "Default"
            case .dark: return "Bubble"
            case .minimalist: return "Minimalist"
            case .sunset: return "Translucent"
            case .ocean: return "Pixel"
            /*
            case .neon: return "Neon"
            case .retro: return "Retro"
            case .gold: return "Gold"
            */
            }
        }
        
        var previewImage: String {
            switch self {
            case .primary: return "sun.max.fill"
            case .dark: return "moon.fill"
            case .minimalist: return "cloud.fill"
            case .sunset: return "sun.haze.fill"
            case .ocean: return "water.waves"
            /*
            case .neon: return "bolt.fill"
            case .retro: return "gamecontroller.fill"
            case .gold: return "crown.fill"
            */
            }
        }
        
        var previewImageName: String {
            switch self {
            case .primary: return "DefaultIconPreview"
            case .dark: return "DarkIconPreview"
            case .minimalist: return "MinimalistIconPreview"
            case .sunset: return "SunsetIconPreview"
            case .ocean: return "OceanIconPreview"
            /*
            case .neon: return "NeonIcon"
            case .retro: return "RetroIcon"
            case .gold: return "GoldIcon"
            */
            }
        }
    }
    
    // Async/Await version
    @MainActor
    func setIcon(_ icon: AppIcon) async -> Bool {
        guard UIApplication.shared.supportsAlternateIcons else { return false }
        
        let iconName: String? = icon == .primary ? nil : icon.rawValue
        
        // Prevent redundant calls
        if iconName == UIApplication.shared.alternateIconName {
             return true 
        }
        
        do {
            try await UIApplication.shared.setAlternateIconName(iconName)
            print("✅ Successfully changed app icon to: \(icon.displayName)")
            self.currentIcon = icon
            
            // Artificial delay to allow system propagation
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            return true
        } catch {
            print("❌ Failed to set app icon: \(error.localizedDescription)")
            return false
        }
    }
}
