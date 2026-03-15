//
//  MinuteForecast.swift
//  Breezy
//
//  Minute-by-minute precipitation forecast model
//

import Foundation

struct MinuteForecast: Identifiable, Codable, Equatable {
    var id: TimeInterval { time.timeIntervalSince1970 }
    let time: Date
    let precipitationChance: Double // 0.0 to 1.0
    let precipitationIntensity: Double // mm/h
    let isPrecipitating: Bool
}
