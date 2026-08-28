//
//  BackgroundTaskManager.swift
//  Breezy
//
//  Simple battery-aware refresh manager
//

import Foundation
import UIKit

class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()
    
    private init() {}
    
    // MARK: - Battery Awareness
    
    /// Returns true if we should limit background activity due to low battery
    func shouldLimitBackgroundActivity() -> Bool {
        let batteryLevel = UIDevice.current.batteryLevel
        let batteryState = UIDevice.current.batteryState
        
        // Enable battery monitoring if not already enabled
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        // Limit background activity if battery is low and not charging
        if batteryState != .charging && batteryState != .full {
            return batteryLevel < 0.10 // Less than 10%
        }
        
        return false
    }
}
