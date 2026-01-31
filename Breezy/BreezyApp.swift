//
//  BreezyApp.swift
//  Breezy
//
//  Created by Oli Mebberson on 31/10/2025.
//

import SwiftUI
import WidgetKit
import SwiftData
import UserNotifications

@main
struct BreezyApp: App {
    var sharedModelContainer: ModelContainer? = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Log error but don't crash - app can still function without SwiftData
            print("Warning: Could not create ModelContainer: \(error)")
            return nil
        }
    }()

    @AppStorage("Breezy.appearanceMode") private var appearanceModeRaw: String = "auto"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(AppearanceMode(rawValue: appearanceModeRaw)?.colorScheme)
                .onAppear {
                    Task {
                        // Start Watch Session immediately
                        WatchSessionManager.shared.startSession()
                        
                        // Delay briefly so app initialization completes, then request widget refresh
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        await MainActor.run {
                            WidgetCenter.shared.reloadAllTimelines()
                        }
                    }
                    // Register for notification taps
                    NotificationCenter.default.addObserver(
                        forName: NSNotification.Name("OpenWeatherDetails"),
                        object: nil,
                        queue: .main
                    ) { _ in
                        // Notification tap will open the app, which is handled automatically
                        // Additional navigation can be added here if needed
                    }
                }
                .fontDesign(WeatherFont(rawValue: UserDefaults.standard.string(forKey: "Breezy.typography") ?? "")?.design ?? .default)
        }
        .modelContainer(for: [Item.self])
    }
}

// MARK: - Onboarding Check

extension View {
    func shouldShowOnboarding() -> Bool {
        !UserDefaults.standard.bool(forKey: "Breezy.HasCompletedOnboarding")
    }
}
