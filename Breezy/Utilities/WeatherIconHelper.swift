//
//  WeatherIconHelper.swift
//  Breezy
//
//  Weather condition icon/emoji helpers
//

import Foundation

struct WeatherIconHelper {
    /// Emoji for a condition. Day/night entries (clear sky) prefer an explicit
    /// daylight flag, then the hour of the forecast date, falling back to the
    /// device clock only when nothing else is known — forecast rows must never
    /// render night icons just because the user opened the app at night.
    static func emoji(for condition: String, isDaylight: Bool? = nil, at date: Date? = nil, in timeZone: TimeZone? = nil) -> String {
        let cond = condition.lowercased()

        if cond.contains("sun") || cond.contains("sunny") { return "☀️" }
        if cond.contains("clear") || cond.contains("mostly clear") {
            return isNight(isDaylight: isDaylight, at: date, in: timeZone) ? "🌙" : "☀️"
        }
        if cond.contains("thunder") { return "⛈️" }
        if cond.contains("shower") { return "🌦️" }
        if cond.contains("rain") || cond.contains("drizzle") { return "🌧️" }
        if cond.contains("sleet") || cond.contains("flurries") || cond.contains("snow") || cond.contains("blizzard") { return "❄️" }
        if cond.contains("haze") || cond.contains("fog") || cond.contains("mist") { return "🌫️" }
        if cond.contains("overcast") { return "☁️" }
        if cond.contains("partly") || cond.contains("cloud") { return "⛅️" }
        if cond.contains("wind") || cond.contains("breeze") || cond.contains("gust") { return "💨" }

        return isNight(isDaylight: isDaylight, at: date, in: timeZone) ? "🌙" : "🌡️"
    }

    static func minimalistIcon(for condition: String, isDaylight: Bool? = nil, at date: Date? = nil, in timeZone: TimeZone? = nil) -> String {
        let cond = condition.lowercased()

        if cond.contains("sun") || cond.contains("sunny") {
            return isNight(isDaylight: isDaylight, at: date, in: timeZone) ? "moon.stars" : "sun.max"
        }
        if cond.contains("clear") || cond.contains("mostly clear") {
            return isNight(isDaylight: isDaylight, at: date, in: timeZone) ? "moon.stars" : "sun.max"
        }
        if cond.contains("partly") && isNight(isDaylight: isDaylight, at: date, in: timeZone) { return "cloud.moon" }
        if cond.contains("thunder") { return "cloud.bolt" }
        if cond.contains("shower") { return "cloud.sun.rain" }
        if cond.contains("rain") || cond.contains("drizzle") { return "cloud.rain" }
        if cond.contains("sleet") || cond.contains("flurries") || cond.contains("snow") || cond.contains("blizzard") { return "cloud.snow" }
        if cond.contains("haze") || cond.contains("fog") || cond.contains("mist") { return "cloud.fog" }
        if cond.contains("overcast") { return "cloud" }
        if cond.contains("partly") { return "cloud.sun" }
        if cond.contains("cloud") { return "cloud" }
        if cond.contains("wind") || cond.contains("breeze") || cond.contains("gust") { return "wind" }

        return "cloud"
    }

    /// Night test: explicit daylight flag wins, then the given date's hour
    /// evaluated in the given (location) timezone, then the device clock.
    private static func isNight(isDaylight: Bool?, at date: Date?, in timeZone: TimeZone? = nil) -> Bool {
        if let isDaylight { return !isDaylight }
        var calendar = Calendar.current
        if let timeZone { calendar.timeZone = timeZone }
        let hour = calendar.component(.hour, from: date ?? Date())
        return hour >= 20 || hour < 6
    }
}
