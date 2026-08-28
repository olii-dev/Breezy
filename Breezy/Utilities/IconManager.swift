//
//  IconManager.swift
//  Breezy
//
//  App Icon Switching Manager. Alternate icons are an iOS-only feature; on
//  macOS the enum stays for gallery previews and setIcon simply fails.
//

import Combine
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

class IconManager: ObservableObject {
    static let shared = IconManager()

    @Published var currentIcon: AppIcon

    private init() {
        #if canImport(UIKit)
        // Initialize currentIcon based on system state
        if let iconName = UIApplication.shared.alternateIconName {
            self.currentIcon = AppIcon(rawValue: iconName) ?? .primary
        } else {
            self.currentIcon = .primary
        }
        #else
        self.currentIcon = .primary
        #endif
    }

    enum AppIcon: String, CaseIterable {
        case primary = "Default"
        case glassCloud = "GlassCloudIcon"
        case nightGlow = "NightGlowIcon"
        case dark = "DarkIcon"
        case sunset = "SunsetIcon"
        case minimalist = "MinimalistIcon"

        var displayName: String {
            switch self {
            case .primary: return "Default"
            case .glassCloud: return "Glass Cloud"
            case .nightGlow: return "Night Glow"
            case .dark: return "Bubble"
            case .minimalist: return "Minimalist"
            case .sunset: return "Translucent"
            }
        }

        var previewImage: String {
            switch self {
            case .primary: return "sun.max.fill"
            case .glassCloud: return "cloud.sun.fill"
            case .nightGlow: return "moon.stars.fill"
            case .dark: return "moon.fill"
            case .minimalist: return "cloud.fill"
            case .sunset: return "sun.haze.fill"
            }
        }

        var previewImageName: String {
            switch self {
            case .primary: return "DefaultIconPreview"
            case .glassCloud: return "GlassCloudIconPreview"
            case .nightGlow: return "NightGlowIconPreview"
            case .dark: return "DarkIconPreview"
            case .minimalist: return "MinimalistIconPreview"
            case .sunset: return "SunsetIconPreview"
            }
        }
    }

    // Async/Await version
    @MainActor
    func setIcon(_ icon: AppIcon) async -> Bool {
        #if canImport(UIKit)
        guard UIApplication.shared.supportsAlternateIcons else { return false }

        let iconName: String? = icon == .primary ? nil : icon.rawValue

        // Prevent redundant calls
        if iconName == UIApplication.shared.alternateIconName {
             return true
        }

        do {
            try await UIApplication.shared.setAlternateIconName(iconName)
            self.currentIcon = icon

            // Artificial delay to allow system propagation
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }
}
