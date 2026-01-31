//
//  Breezy_WatchApp.swift
//  Breezy Watch Watch App
//
//  Apple Watch app entry point
//

import SwiftUI
import WidgetKit

@main
struct Breezy_Watch_Watch_AppApp: App {
    @StateObject private var viewModel = WatchWeatherViewModel()
    
    init() {
        // Reload widget timelines when app launches
        Task {
            // Small delay to ensure app is fully initialized
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            await MainActor.run {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        
        // Setup background refresh
        BackgroundRefreshManager.shared.setupBackgroundRefresh()
        
        // Start Sync Session
        WatchSessionManager.shared.startSession()
    }
    
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
                    .environmentObject(viewModel)
                    .task {
                        // Load weather on app launch
                        await viewModel.loadWeather()
                    }
            }
            .fontDesign(viewModel.typography.design)
        }
    }
}
