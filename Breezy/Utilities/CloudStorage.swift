//
//  CloudStorage.swift
//  Breezy
//
//  Helper to sync settings with iCloud persistence
//

import Foundation

class CloudStorage {
    static let shared = CloudStorage()
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
        // This handles cases where user installs app on a new device
        // or re-installs it.
        let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
        
        for key in changedKeys {
            if let cloudValue = cloudStore.object(forKey: key) {
                UserDefaults.standard.set(cloudValue, forKey: key)
            }
        }
        
        // Notify app components to refresh
        NotificationCenter.default.post(name: .cloudDataReconciled, object: nil)
    }
    
    func set(_ value: Any?, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
        cloudStore.set(value, forKey: key)
        cloudStore.synchronize()
    }
    
    func data(forKey key: String) -> Data? {
        // Priority: Local Cache -> Cloud
        return UserDefaults.standard.data(forKey: key) ?? cloudStore.data(forKey: key)
    }
    
    func string(forKey key: String) -> String? {
        return UserDefaults.standard.string(forKey: key) ?? cloudStore.string(forKey: key)
    }
    
    func bool(forKey key: String) -> Bool {
        if UserDefaults.standard.object(forKey: key) != nil {
            return UserDefaults.standard.bool(forKey: key)
        }
        return cloudStore.bool(forKey: key)
    }
    
    func synchronize() {
        cloudStore.synchronize()
    }
}

extension Notification.Name {
    static let cloudDataReconciled = Notification.Name("BreezyCloudDataReconciled")
}
