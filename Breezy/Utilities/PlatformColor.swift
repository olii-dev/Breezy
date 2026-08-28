//
//  PlatformColor.swift
//  Breezy
//
//  Cross-platform RGB access for SwiftUI Colors (UIColor on iOS, NSColor on
//  macOS) so shared models and themes compile natively on both platforms.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum PlatformColor {
    /// sRGB components (r, g, b, a) in 0...1, or nil if they can't be read.
    static func rgbaComponents(of color: Color) -> (r: Double, g: Double, b: Double, a: Double)? {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return (Double(r), Double(g), Double(b), Double(a))
        #elseif canImport(AppKit)
        guard let srgb = NSColor(color).usingColorSpace(.sRGB),
              let components = srgb.cgColor.components else { return nil }
        switch components.count {
        case 2:  return (Double(components[0]), Double(components[0]), Double(components[0]), Double(components[1]))
        case 4:  return (Double(components[0]), Double(components[1]), Double(components[2]), Double(components[3]))
        default: return nil
        }
        #else
        return nil
        #endif
    }
}
