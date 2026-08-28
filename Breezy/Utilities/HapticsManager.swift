//
//  HapticsManager.swift
//  Breezy
//
//  Centralized manager for haptic feedback. No-ops on macOS (no Taptic
//  engine) while keeping the exact same call-site API.
//

#if canImport(UIKit)
import UIKit

class HapticsManager {
    static let shared = HapticsManager()

    private init() {}

    func selectionChanged() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}

#else

/// macOS stand-in matching the UIKit call-site surface.
class HapticsManager {
    static let shared = HapticsManager()

    private init() {}

    enum FeedbackStyle {
        case light, medium, heavy, soft, rigid
    }

    enum FeedbackType {
        case success, warning, error
    }

    func selectionChanged() {}
    func impact(style: FeedbackStyle) {}
    func notification(type: FeedbackType) {}
}

#endif
