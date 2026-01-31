//
//  WatchCloudStorage.swift
//  BreezyWatch Watch App
//
//  Helper to sync settings with iCloud persistence on Watch
//

import Foundation

class WatchCloudStorage {
    static let shared = WatchCloudStorage()
    // WatchOS uses the same default ubiquitous store as the iOS app for the same iCloud account
    private let cloudStore = NSUbiquitousKeyValueStore.default
    
    private init() {
        // Observe cloud changes to keep local storage in sync
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudDataChanged),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore
        )
        cloudStore.synchronize()
    }
    
    @objc private func cloudDataChanged(notification: Notification) {
        // When cloud changes, pull to local UserDefaults if needed
        let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
        
        print("⌚️ WATCH: Cloud Data Changed Keys: \(changedKeys)")
        
        for key in changedKeys {
            if let cloudValue = cloudStore.object(forKey: key) {
                UserDefaults.standard.set(cloudValue, forKey: key)
            }
        }
        
        // Notify app components to refresh
        NotificationCenter.default.post(name: .watchCloudDataReconciled, object: nil)
    }
    
    func set(_ value: Any?, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        cloudStore.set(value, forKey: key)
        cloudStore.synchronize()
    }
    
    func string(forKey key: String) -> String? {
        return UserDefaults.standard.string(forKey: key) ?? cloudStore.string(forKey: key)
    }
    
    func synchronize() {
        cloudStore.synchronize()
    }
}

extension Notification.Name {
    static let watchCloudDataReconciled = Notification.Name("BreezyWatchCloudDataReconciled")
}
