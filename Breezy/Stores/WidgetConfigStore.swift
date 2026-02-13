//
//  WidgetConfigStore.swift
//  Breezy
//
//  Created for Custom Widget Builder
//

import Foundation
import SwiftUI
import WidgetKit
import Combine

class WidgetConfigStore: ObservableObject {
    static let shared = WidgetConfigStore()
    private let suiteName = "group.com.breezy.weather"
    private let key = "Breezy.CustomWidgetConfig"
    
    @Published var currentConfig: CustomWidgetConfiguration
    
    init() {
        self.currentConfig = CustomWidgetConfiguration.default
        load()
    }
    
    func load() {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: key) else {
            return
        }
        
        do {
            let decoded = try JSONDecoder().decode(CustomWidgetConfiguration.self, from: data)
            self.currentConfig = decoded
        } catch {
            print("WidgetConfigStore: Failed to decode config: \(error)")
        }
    }
    
    func save(_ config: CustomWidgetConfiguration) {
        self.currentConfig = config
        
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            print("WidgetConfigStore: Failed to access App Group defaults")
            return
        }
        
        do {
            let data = try JSONEncoder().encode(config)
            defaults.set(data, forKey: key)
            WidgetCenter.shared.reloadAllTimelines()
            print("WidgetConfigStore: Saved config and reloaded timelines")
        } catch {
            print("WidgetConfigStore: Failed to encode config: \(error)")
        }
    }
    
    func reset() {
        save(CustomWidgetConfiguration.default)
    }
}
