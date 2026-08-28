import SwiftUI

extension Color {
    /// Platform-neutral encoding (hex text) so custom themes survive iCloud
    /// sync between iOS and macOS. Legacy archived blobs still decode via the
    /// native path on iOS.
    func toData() -> Data? {
        if let hex = toHex() {
            return Data(hex.utf8)
        }
        #if canImport(UIKit)
        return try? NSKeyedArchiver.archivedData(withRootObject: UIColor(self), requiringSecureCoding: false)
        #elseif canImport(AppKit)
        return try? NSKeyedArchiver.archivedData(withRootObject: NSColor(self), requiringSecureCoding: false)
        #else
        return nil
        #endif
    }

    static func fromData(_ data: Data) -> Color? {
        // New portable format: bare hex text (6 or 8 digits).
        if let hex = String(data: data, encoding: .utf8),
           hex.count == 6 || hex.count == 8,
           hex.allSatisfy({ $0.isHexDigit }) {
            return Color(hex: hex)
        }
        #if canImport(UIKit)
        if let uiColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: UIColor.self, from: data) {
            return Color(uiColor)
        }
        #elseif canImport(AppKit)
        if let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
            return Color(nsColor)
        }
        #endif
        return nil
    }

    func toHex() -> String? {
        guard let c = PlatformColor.rgbaComponents(of: self) else {
            return nil
        }
        let r = Float(c.r)
        let g = Float(c.g)
        let b = Float(c.b)
        var a = Float(c.a)

        if a != 1.0 {
            return String(format: "%02lX%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255), lroundf(a * 255))
        } else {
            return String(format: "%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
        }
    }
}
