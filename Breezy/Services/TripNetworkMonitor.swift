//
//  TripNetworkMonitor.swift
//  Breezy
//
//  Lightweight reachability for offline trip / Live Activity labeling.
//

import Foundation
import Network
import Combine

@MainActor
final class TripNetworkMonitor: ObservableObject {
    static let shared = TripNetworkMonitor()

    @Published private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "Breezy.TripNetworkMonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
}
