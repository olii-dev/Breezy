//
//  BreezyMacApp.swift
//  BreezyMac
//
//  Native macOS app entry: main window (sidebar + dashboard), per-location
//  windows, native Settings, and a Weather command menu.
//

import SwiftUI
import WidgetKit

@main
struct BreezyMacApp: App {
    @AppStorage("Breezy.appearanceMode") private var appearanceModeRaw: String = "auto"

    var body: some Scene {
        WindowGroup(id: "main") {
            MacRootView()
                .preferredColorScheme(AppearanceMode(rawValue: appearanceModeRaw)?.colorScheme)
                .fontDesign(WeatherFont(rawValue: UserDefaults.standard.string(forKey: "Breezy.typography") ?? "")?.design ?? .default)
                .frame(minWidth: 720, minHeight: 520)
        }
        .defaultSize(width: 1120, height: 780)
        .commands {
            MacCommands()
        }

        WindowGroup("Location", id: "location", for: LocationData.self) { $location in
            MacLocationWindowView(location: location)
                .preferredColorScheme(AppearanceMode(rawValue: appearanceModeRaw)?.colorScheme)
                .fontDesign(WeatherFont(rawValue: UserDefaults.standard.string(forKey: "Breezy.typography") ?? "")?.design ?? .default)
                .frame(minWidth: 680, minHeight: 480)
        }
        .defaultSize(width: 1120, height: 780)

        Settings {
            MacSettingsHost()
        }
    }
}

/// Menu-bar extras beyond the defaults.
struct MacCommands: Commands {
    var body: some Commands {
        CommandMenu("Weather") {
            Button("Refresh") {
                NotificationCenter.default.post(name: .macRefreshRequested, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Time Machine…") {
                NotificationCenter.default.post(name: .macTimeMachineRequested, object: nil)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Divider()

            Button("Radar") {
                NotificationCenter.default.post(name: .macRadarRequested, object: nil)
            }
            .keyboardShortcut("0", modifiers: .command)
        }
    }
}

extension Notification.Name {
    static let macRefreshRequested = Notification.Name("Mac.RefreshRequested")
    static let macTimeMachineRequested = Notification.Name("Mac.TimeMachineRequested")
    static let macRadarRequested = Notification.Name("Mac.RadarRequested")
}
