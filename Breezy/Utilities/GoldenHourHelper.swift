//
//  GoldenHourHelper.swift
//  Breezy
//
//  Golden hour window calculations shared by the dashboard card
//  and the day-detail view.
//

import Foundation

enum GoldenHourHelper {
    struct Window: Equatable {
        let start: Date
        let end: Date
    }

    /// Morning golden hour runs from 1 hour before sunrise to 30 minutes after.
    /// Evening golden hour runs from 30 minutes before sunset to 1 hour after.
    static func window(sunDate: Date, isMorning: Bool) -> Window {
        if isMorning {
            let start = Calendar.current.date(byAdding: .hour, value: -1, to: sunDate) ?? sunDate
            let end = Calendar.current.date(byAdding: .minute, value: 30, to: sunDate) ?? sunDate
            return Window(start: start, end: end)
        } else {
            let start = Calendar.current.date(byAdding: .minute, value: -30, to: sunDate) ?? sunDate
            let end = Calendar.current.date(byAdding: .hour, value: 1, to: sunDate) ?? sunDate
            return Window(start: start, end: end)
        }
    }

    static func isGoldenHour(now: Date = Date(), window: Window) -> Bool {
        now >= window.start && now <= window.end
    }

    static func isGoldenHour(sunDate: Date?, isMorning: Bool, now: Date = Date()) -> Bool {
        guard let sunDate else { return false }
        return isGoldenHour(now: now, window: window(sunDate: sunDate, isMorning: isMorning))
    }
}