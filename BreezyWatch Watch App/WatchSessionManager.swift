//
//  WatchSessionManager.swift
//  BreezyWatch Watch App
//
//  Manages Watch Connectivity session on WatchOS
//

import Foundation
import WatchConnectivity
import Combine

class WatchSessionManager: NSObject, WCSessionDelegate, ObservableObject {
    static let shared = WatchSessionManager()
    
    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    weak var viewModel: WatchWeatherViewModel?
    
    private override init() {
        super.init()
        session?.delegate = self
        session?.activate()
    }
    
    func startSession() {
        if session?.activationState != .activated {
            session?.activate()
        }
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("⌚️ WATCH: Activation complete. State: \(activationState.rawValue), Error: \(String(describing: error))")
        if let error = error {
            print("⌚️ WATCH: Activation failed: \(error.localizedDescription)")
        } else if activationState == .activated {
            // Check for pending background context updates
            let context = session.receivedApplicationContext
            if !context.isEmpty {
                print("⌚️ WATCH: Found pending application context on activation")
                DispatchQueue.main.async {
                    self.viewModel?.updateFromContext(context)
                }
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        print("⌚️ WATCH: Received background context with \(applicationContext.count) items")
        DispatchQueue.main.async {
            self.viewModel?.updateFromContext(applicationContext)
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("⌚️ WATCH: Received INSTANT message with \(message.count) items")
        DispatchQueue.main.async {
            self.viewModel?.updateFromContext(message)
        }
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        print("⌚️ WATCH: Received UserInfo transfer with \(userInfo.count) items")
        DispatchQueue.main.async {
            self.viewModel?.updateFromContext(userInfo)
        }
    }
}
