//
//  TripAheadAlertScheduler.swift
//  Breezy
//
//  Local notifications for weather ahead while a trip is live.
//

import Foundation
import UserNotifications

final class TripAheadAlertScheduler {
    static let shared = TripAheadAlertScheduler()

    private let center = UNUserNotificationCenter.current()
    private let prefix = "breezy.trip.ahead."

    private init() {}

    func schedule(for route: TripRouteOption, destinationName: String) {
        cancel()

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }

            let now = Date()
            // Notify ~20 minutes before notable weather samples (cap 6 alerts).
            let candidates = route.samples.filter { sample in
                guard sample.eta > now.addingTimeInterval(5 * 60) else { return false }
                if !sample.riskFlags.isEmpty { return true }
                return (sample.weather?.precipitationProbability ?? 0) >= 0.55
            }

            for (index, sample) in candidates.prefix(6).enumerated() {
                let fireDate = sample.eta.addingTimeInterval(-20 * 60)
                guard fireDate > now else { continue }

                let content = UNMutableNotificationContent()
                content.title = "Weather ahead"
                if let flag = sample.riskFlags.first {
                    content.body = "\(flag.title) near \(sample.placeLabel.isEmpty ? destinationName : sample.placeLabel) in about 20 minutes."
                } else if let weather = sample.weather {
                    content.body = "\(weather.condition) (\(weather.formattedTemperature)) ahead on your drive to \(destinationName)."
                } else {
                    content.body = "Changing conditions ahead on your drive to \(destinationName)."
                }
                content.sound = .default

                let interval = max(5, fireDate.timeIntervalSince(now))
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "\(self.prefix)\(index)",
                    content: content,
                    trigger: trigger
                )
                self.center.add(request, withCompletionHandler: nil)
            }
        }
    }

    func cancel() {
        center.getPendingNotificationRequests { [prefix] requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}
