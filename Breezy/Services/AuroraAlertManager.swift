//
//  AuroraAlertManager.swift
//  Breezy
//
//  Runs alongside every weather fetch: pulls NOAA SWPC (rate-limited), assesses
//  aurora visibility for the current location (Kp vs latitude, Bz, darkness,
//  cloud, moon), persists the widget snapshot, and fires a notification when
//  conditions clear the bar. Serverless by design — the "real-time" caveat is
//  the same as the lightning feed: checks happen when Breezy gets CPU time.
//

import Foundation
import UserNotifications
import WidgetKit

@MainActor
final class AuroraAlertManager {
    static let shared = AuroraAlertManager()

    /// NOAA product updates ~every 3 h (Kp) / 1 min (solar wind); 15 min is a
    /// polite fetch cadence that still catches evening escalations.
    private let minimumRefetchInterval: TimeInterval = 15 * 60
    /// Same alert can't repeat inside this window unless Kp climbs a full step.
    private let alertCooldown: TimeInterval = 6 * 60 * 60

    private let center = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - Cooldown state

    private struct AlertState: Codable {
        var lastAlertAt: Date?
        var lastAlertKp: Double?
    }

    private var alertState: AlertState {
        get {
            guard let defaults = UserDefaults(suiteName: "group.com.breezy.weather"),
                  let data = defaults.data(forKey: "Breezy.aurora.alertState"),
                  let decoded = try? JSONDecoder().decode(AlertState.self, from: data) else {
                return AlertState()
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults(suiteName: "group.com.breezy.weather")?.set(data, forKey: "Breezy.aurora.alertState")
            }
        }
    }

    // MARK: - Entry point (called after every successful weather fetch)

    func update(with weather: WeatherInfo) {
        let settings = UserDefaults.standard.notificationSettings
        var snapshot = AuroraStore.load() ?? AuroraKit.Snapshot(
            kp: nil, requiredKp: nil, bzNanoteslas: nil, solarWindSpeed: nil,
            cloudFraction: nil, moonIllumination: nil, isNight: true,
            verdict: "Waiting for data", detail: "NOAA feed not fetched yet",
            score: 0, latitude: weather.location.latitude, fetchedAt: .distantPast
        )

        // Cheap local refresh: darkness/cloud/moon move with the weather, and
        // the verdict should track them even when NOAA hasn't been re-fetched.
        refresh(snapshot: &snapshot, weather: weather, latitude: weather.location.latitude, settings: settings)
        AuroraStore.save(snapshot)
        AuroraLiveActivityManager.shared.update(snapshot: snapshot, weather: weather)
        checkForAlert(snapshot: snapshot, settings: settings)

        // Rate-limited NOAA refetch — keep the Kp itself fresh.
        guard snapshot.fetchedAt.addingTimeInterval(minimumRefetchInterval) <= Date() else { return }

        let latitude = weather.location.latitude
        Task { [weak self] in
            guard let fresh = await AuroraService.fetchSnapshot(latitude: latitude) else { return }
            guard let self else { return }
            var snapshot = fresh
            self.refresh(snapshot: &snapshot, weather: weather, latitude: latitude, settings: settings)
            AuroraStore.save(snapshot)
            WidgetCenter.shared.reloadTimelines(ofKind: "BreezyStargazingWidget")
            AuroraLiveActivityManager.shared.update(snapshot: snapshot, weather: weather)
            self.checkForAlert(snapshot: snapshot, settings: settings)
        }
    }

    /// Fill in the local-halves of a NOAA snapshot and compute the verdict.
    private func refresh(snapshot: inout AuroraKit.Snapshot, weather: WeatherInfo, latitude: Double, settings: NotificationSettings) {
        let today = weather.dailyForecast.first
        let now = Date()

        var night = true
        if let sunrise = today?.sunriseDate, let sunset = today?.sunsetDate {
            night = now < sunrise || now >= sunset
        }

        var cloudFraction: Double?
        if let text = weather.metrics?.cloudCover?.replacingOccurrences(of: "%", with: ""),
           let percent = Double(text) {
            cloudFraction = max(0, min(1, percent / 100))
        }

        let moonIllumination = today?.moonPhase?.illumination

        snapshot.latitude = latitude
        snapshot.isNight = night
        snapshot.cloudFraction = cloudFraction
        snapshot.moonIllumination = moonIllumination

        let required = AuroraKit.requiredKp(latitude: latitude)
        snapshot.requiredKp = required

        guard let kp = snapshot.kp else { return }
        // A user-picked floor can only raise the bar, never lower it — the
        // latitude math is physics, the picker is preference.
        let effectiveRequired = max(required, Double(settings.auroraMinKp))
        let assessment = AuroraKit.assess(
            kp: kp,
            bzNanoteslas: snapshot.bzNanoteslas,
            latitude: latitude,
            cloudFraction: cloudFraction,
            moonIllumination: moonIllumination,
            isNight: night
        )
        snapshot.verdict = assessment.verdict
        snapshot.detail = assessment.detail
        snapshot.score = assessment.score
        // Honor a raised bar: under the personal floor caps the score below
        // the active line so notifications and widgets stay quiet.
        if effectiveRequired > required && kp < effectiveRequired {
            snapshot.score = min(snapshot.score, 0.3)
        }
    }

    // MARK: - Notification

    private func checkForAlert(snapshot: AuroraKit.Snapshot, settings: NotificationSettings) {
        guard settings.auroraAlertsEnabled, snapshot.isActive, let kp = snapshot.kp else { return }

        let state = alertState
        if let lastAt = state.lastAlertAt {
            let elapsed = Date().timeIntervalSince(lastAt)
            let escalation = (state.lastAlertKp ?? 0) > 0 && kp >= (state.lastAlertKp ?? 0) + 1
            guard elapsed >= alertCooldown || escalation else { return }
        }

        alertState = AlertState(lastAlertAt: Date(), lastAlertKp: kp)

        let content = UNMutableNotificationContent()
        content.title = "Aurora possible tonight"
        var body = "Kp \(AuroraKit.formatted(kp))"
        if let bz = snapshot.bzNanoteslas, bz <= -5 { body += ", solar wind is coupling (Bz \(Int(bz)) nT)" }
        if let cloud = snapshot.cloudFraction { body += cloud < 0.3 ? ", skies are clear" : ", \(Int((cloud * 100).rounded()))% cloud — find a gap" }
        if let moon = snapshot.moonIllumination, moon > 0.5 { body += ", moon is \(Int((moon * 100).rounded()))% — darker spots help" }
        content.body = body + ". Look south if you're in Australia."
        content.sound = .default
        content.userInfo = ["type": "aurora"]

        center.add(UNNotificationRequest(
            identifier: "aurora.\(UUID().uuidString)",
            content: content,
            trigger: nil
        ))
    }
}
