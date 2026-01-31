//
//  DateFormatterHelper.swift
//  Breezy
//
//  Date formatting utilities
//

import Foundation

struct DateFormatterHelper {
    static func formatTime(_ date: Date, timeZone: TimeZone? = nil) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        if let timeZone = timeZone {
            formatter.timeZone = timeZone
        }
        return formatter.string(from: date)
    }
    
    static func formatHour(_ hour: Int) -> String {
        hour == 0 ? "12AM" :
        hour < 12 ? "\(hour)AM" :
        hour == 12 ? "12PM" : "\(hour - 12)PM"
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
}

