//
//  LightningAlertManager.swift
//  Breezy
//
//  Live proximity alerts from the Blitzortung feed: when a strike lands
//  within range of the user's location, post an immediate notification.
//  Serverless reality: the websocket only delivers while the app is alive,
//  so these fire while Breezy is open or a radar surface is showing — the
//  forecast-driven half of lightning alerts lives in NotificationManager
//  and works with the app closed.
//

import Foundation
import CoreLocation
import UserNotifications

@MainActor
final class LightningAlertManager {
    static let shared = LightningAlertManager()

    /// Updated by the view model after every weather fetch.
    var userCoordinate: CLLocationCoordinate2D?

    private var lastAlertDate: Date?
    private let proximityThreshold: CLLocationDistance = 20_000
    private let closeThreshold: CLLocationDistance = 8_000
    private let cooldown: TimeInterval = 15 * 60

    private var enabled: Bool {
        UserDefaults.standard.notificationSettings.lightningAlertsEnabled
    }

    private init() {
        LightningService.shared.onStrikeAdded = { [weak self] strike in
            Task { @MainActor in
                self?.evaluate(strike: strike)
            }
        }
    }

    private func evaluate(strike: LightningStrike) {
        guard enabled else { return }
        guard notificationPermissionLikelyGranted else { return }
        guard let userCoordinate else { return }

        let origin = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        let strikeLocation = CLLocation(latitude: strike.coordinate.latitude, longitude: strike.coordinate.longitude)
        let distance = origin.distance(from: strikeLocation)
        guard distance <= proximityThreshold else { return }

        // Cooldown — one proximity alert per window even in an active cell.
        if let last = lastAlertDate, Date().timeIntervalSince(last) < cooldown { return }
        lastAlertDate = Date()

        let content = UNMutableNotificationContent()
        content.title = "Lightning Nearby"
        if distance <= closeThreshold {
            content.body = String(format: "A strike landed %.0f km away. Go indoors and stay away from windows.", distance / 1000)
        } else {
            content.body = String(format: "A strike landed %.0f km away — a storm is close enough to reach you soon.", distance / 1000)
        }
        content.sound = .default
        content.categoryIdentifier = "WEATHER_ALERT"
        content.userInfo = ["type": "lightning", "distanceMeters": Int(distance)]

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "lightning.\(UUID().uuidString)", content: content, trigger: nil)
        )
    }

    /// Cheap gate to avoid posting into the void when permission was denied.
    private var notificationPermissionLikelyGranted: Bool {
        NotificationManager.shared.authorizationStatus == .authorized
    }
}
