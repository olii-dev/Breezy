//
//  TripControlIntents.swift
//  Breezy
//
//  Buttons ON the trip Live Activity: pause freezes tracking (activity
//  stays, showing Paused), resume re-arms GPS, end dismisses everything.
//  LiveActivityIntent so they can run straight from the Lock Screen /
//  Dynamic Island / CarPlay dashboard tap.
//

import Foundation
import AppIntents

/// Shared indirection: the widget target renders the LA buttons (so the
/// intents must compile there), but only the app owns the trip manager. The
/// app registers real handlers at launch; LA button taps run the intent in
/// the app process, where the handlers exist.
@MainActor
enum TripControlBus {
    nonisolated(unsafe) static var pause: (@MainActor () -> Void)?
    nonisolated(unsafe) static var resume: (@MainActor () -> Void)?
    nonisolated(unsafe) static var end: (@MainActor () -> Void)?
}

@MainActor
struct PauseTripIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause Trip"
    static let description = IntentDescription("Freeze trip tracking without ending it.")

    func perform() async throws -> some IntentResult {
        TripControlBus.pause?()
        return .result()
    }
}

@MainActor
struct ResumeTripIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume Trip"
    static let description = IntentDescription("Continue the paused trip.")

    func perform() async throws -> some IntentResult {
        TripControlBus.resume?()
        return .result()
    }
}

@MainActor
struct EndTripIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End Trip"
    static let description = IntentDescription("End the trip and dismiss its Live Activity.")

    func perform() async throws -> some IntentResult {
        TripControlBus.end?()
        return .result()
    }
}
