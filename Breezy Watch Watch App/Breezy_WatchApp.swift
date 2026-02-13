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
    @WKApplicationDelegateAdaptor(ExtensionDelegate.self) var delegate
    @StateObject private var viewModel = WatchWeatherViewModel()
    
    init() {
        // No-op: Moved setup to ExtensionDelegate to prevent crash
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

class ExtensionDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        // Setup background refresh
        BackgroundRefreshManager.shared.setupBackgroundRefresh()
        
        // Start Sync Session
        WatchSessionManager.shared.startSession()
        
        // Reload widgets
        WidgetCenter.shared.reloadAllTimelines()
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        Task {
            await BackgroundRefreshManager.shared.handleBackgroundRefresh(backgroundTasks)
        }
    }
}
