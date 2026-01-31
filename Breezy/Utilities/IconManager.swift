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
        case night = "NightIcon"
        case minimalist = "MinimalistIcon"
        
        var displayName: String {
            switch self {
            case .primary: return "Default"
            case .dark: return "Dark Mode"
            case .night: return "Night"
            case .minimalist: return "Minimalist"
            }
        }
        
        var previewImage: String {
            switch self {
            case .primary: return "sun.max.fill"
            case .dark: return "moon.fill"
            case .night: return "moon.stars.fill"
            case .minimalist: return "cloud.fill"
            }
        }
        
        var previewImageName: String {
            switch self {
            case .primary: return "DefaultIconPreview"
            case .dark: return "DarkIconPreview"
            case .night: return "NightIconPreview"
            case .minimalist: return "MinimalistIconPreview"
            }
        }
    }
    
    // Legacy completion handler version
    func setIcon(_ icon: AppIcon, completion: ((Bool) -> Void)? = nil) {
        guard UIApplication.shared.supportsAlternateIcons else {
            completion?(false)
            return
        }
        
        let iconName: String? = icon == .primary ? nil : icon.rawValue
        
        UIApplication.shared.setAlternateIconName(iconName) { [weak self] error in
            if let error = error {
                print("❌ Failed to set app icon: \(error.localizedDescription)")
                completion?(false)
            } else {
                print("✅ Successfully changed app icon to: \(icon.displayName)")
                DispatchQueue.main.async {
                    self?.currentIcon = icon
                }
                completion?(true)
            }
        }
    }
    
    // Async/Await version
    @MainActor
    func setIcon(_ icon: AppIcon) async -> Bool {
        return await withCheckedContinuation { continuation in
            setIcon(icon) { success in
                continuation.resume(returning: success)
            }
        }
    }
}
