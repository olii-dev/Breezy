//
//  DateFormatterHelper.swift
//  Breezy
//
//  Date formatting utilities
//

import Foundation

struct DateFormatterHelper {
    /// Whether the device uses a 24-hour clock (respects the iOS setting).
    static var uses24HourClock: Bool {
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.current)
        return template?.contains("a") != true
    }

    /// Compact hour label: "5PM" on 12-hour devices, "17" on 24-hour devices.
    static func hourLabel(_ hour: Int) -> String {
        guard !uses24HourClock else { return "\(hour)" }
        switch hour {
        case 0: return "12AM"
        case 12: return "12PM"
        case 1..<12: return "\(hour)AM"
        default: return "\(hour - 12)PM"
        }
    }

    static func formatTime(_ date: Date, timeZone: TimeZone? = nil) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "j:mm", options: 0, locale: Locale.current)
        if let timeZone = timeZone {
            formatter.timeZone = timeZone
        }
        return formatter.string(from: date)
    }
    
    static func formatHour(_ hour: Int) -> String {
        hourLabel(hour)
    }
    
    static func formatDayName(_ date: Date, timeZone: TimeZone? = nil) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        if let timeZone = timeZone {
            formatter.timeZone = timeZone
        }
        return formatter.string(from: date)
    }
    
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    static func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
    
    static func parseTime(_ timeString: String, timeZone: TimeZone? = nil) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "j:mm", options: 0, locale: Locale.current)
        if let timeZone = timeZone {
            formatter.timeZone = timeZone
        }
        // Returns a date on Jan 1, 2000 usually, but we need it for Today
        guard let date = formatter.date(from: timeString) else { return nil }
        
        // Normalize to today
        var calendar = Calendar.current
        if let timeZone = timeZone {
            calendar.timeZone = timeZone
        }
        
        let now = Date()
        let components = calendar.dateComponents([.hour, .minute], from: date)
        
        return calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: now)
    }
}

