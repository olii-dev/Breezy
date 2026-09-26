//
//  LightningService.swift
//  Breezy
//
//  Live lightning strikes from the Blitzortung.org community network.
//
//  Protocol (unofficial, community-documented): connect to
//  wss://ws1.blitzortung.org, send {"a": 111}, then each binary frame is an
//  LZW-compressed JSON document. Strike messages carry "lat"/"lon" in degrees
//  and "time" in epoch nanoseconds, among other fields. The protocol can
//  change without notice, so every decode failure is swallowed and the
//  connection is recycled rather than crashing or spamming errors.
//
//  The service only runs while a radar view is on screen: iOS cannot keep a
//  websocket alive in the background, so callers pair start()/stop() with
//  onAppear/onDisappear. Strikes older than the retention window are pruned.
//

import Foundation
import CoreLocation
import Combine

struct LightningStrike: Identifiable, Equatable {
    /// Stable identity for annotation diffing (time + rounded coordinates).
    let id: String
    let coordinate: CLLocationCoordinate2D
    let date: Date
    /// Reported polarity (+1 negative cloud-ground, -1 positive); informational.
    let polarity: Int?
    /// Number of reporting stations, when present — a rough quality signal.
    let stationCount: Int?

    static func == (lhs: LightningStrike, rhs: LightningStrike) -> Bool {
        lhs.id == rhs.id
    }
}

/// Health of the live strike feed. `.stale` and `.unavailable` distinguish
/// "socket looks alive but the stream went quiet" (possible protocol change)
/// from "repeatedly failing to reconnect".
enum LightningConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case stale
    case unavailable
}

final class LightningService: ObservableObject {

    static let shared = LightningService()

    /// Strikes recorded within the retention window, oldest first.
    @Published private(set) var strikes: [LightningStrike] = []
    /// Feed health, surfaced by the radar UI instead of a silently empty layer.
    @Published private(set) var connectionState: LightningConnectionState = .idle

    /// True while the websocket is established (even if the stream looks stale).
    var isConnected: Bool { connectionState == .connected || connectionState == .stale }

    /// Short status for the radar UI, shown when the layer has no strikes so
    /// a dead feed isn't mistaken for "no lightning anywhere".
    var statusChipText: String? {
        switch connectionState {
        case .stale: return "Lightning feed reconnecting…"
        case .unavailable: return "Lightning feed unavailable"
        default: return nil
        }
    }

    private let retentionInterval: TimeInterval = 30 * 60
    private let servers = ["wss://ws1.blitzortung.org", "wss://ws2.blitzortung.org", "wss://ws3.blitzortung.org"]
    /// Total silence (any frame, not just strikes) for this long counts as a dead stream.
    private let stalenessTimeout: TimeInterval = 90
    /// Consecutive failed reconnects before the feed is reported unavailable.
    private let unavailableAfterAttempts = 4

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var serverIndex = 0
    private var reconnectAttempt = 0
    private var shouldRun = false
    private var pruneTimer: Timer?
    /// Last time any frame arrived (strikes, status, keepalives — anything).
    private var lastMessageAt: Date?
    /// Set once a reconnect cycle has begun after silence, so stale is reported
    /// instead of connected even before the recycle finishes.
    private var recyclingAfterSilence = false

    private let queue = DispatchQueue(label: "Breezy.LightningService")

    private init() {}

    // MARK: - Lifecycle

    func start() {
        queue.async { [weak self] in
            guard let self, !self.shouldRun else { return }
            self.shouldRun = true
            self.lastMessageAt = nil
            self.reconnectAttempt = 0
            self.recyclingAfterSilence = false
            self.setState(.connecting)
            self.connect()
            self.startPruning()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.shouldRun = false
            self.task?.cancel(with: .goingAway, reason: nil)
            self.task = nil
            self.session?.invalidateAndCancel()
            self.session = nil
            self.pruneTimer?.invalidate()
            self.pruneTimer = nil
            self.lastMessageAt = nil
            self.recyclingAfterSilence = false
            self.setState(.idle)
        }
    }

    // MARK: - Connection

    private func connect() {
        guard shouldRun else { return }
        let server = servers[serverIndex % servers.count]
        guard let url = URL(string: server) else { return }

        // State was already set by start() (.connecting) or the recycle path
        // (.stale); connect() itself stays state-neutral.

        let session = URLSession(configuration: .ephemeral)
        self.session = session
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()

        // Handshake: tells the server to start streaming strike messages.
        task.send(.string("{\"a\": 111}")) { [weak self] error in
            guard error == nil else {
                self?.scheduleReconnect()
                return
            }
            // Established — but only call it healthy once frames arrive.
            // lastMessageAt anchors here so a server that never streams is
            // still caught by the staleness check.
            DispatchQueue.main.async {
                guard let self, self.shouldRun, self.connectionState == .connecting else { return }
                self.connectionState = .connected
                if self.lastMessageAt == nil {
                    self.lastMessageAt = Date()
                }
            }
        }
        receiveNext()
    }

    private func receiveNext() {
        guard let task else { return }
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.scheduleReconnect()
            case .success(let message):
                self.handle(message)
                self.queue.async { self.receiveNext() }
            }
        }
    }

    private func scheduleReconnect() {
        queue.async { [weak self] in
            guard let self, self.shouldRun else { return }
            self.task?.cancel(with: .goingAway, reason: nil)
            self.task = nil
            self.session?.invalidateAndCancel()
            self.session = nil
            self.serverIndex += 1
            self.reconnectAttempt += 1

            // While recycling after detected silence the state stays .stale;
            // only enough failed attempts upgrades that to .unavailable.
            if self.reconnectAttempt >= self.unavailableAfterAttempts {
                self.setState(.unavailable)
            } else if !self.recyclingAfterSilence {
                self.setState(.connecting)
            }

            // Exponential backoff, capped at 30s.
            let delay = min(30.0, pow(2.0, Double(min(self.reconnectAttempt, 5))))
            self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.shouldRun else { return }
                self.connect()
            }
        }
    }

    /// Runs on the main timer (prune cadence). Detects a stream that looks
    /// connected but has gone silent — e.g. an undocumented protocol change —
    /// and recycles the connection rather than leaving a quietly empty layer.
    private func checkStaleness() {
        guard shouldRun, task != nil, let last = lastMessageAt else { return }
        guard Date().timeIntervalSince(last) > stalenessTimeout else { return }

        recyclingAfterSilence = true
        connectionState = .stale
        scheduleReconnect()
    }

    private func setState(_ state: LightningConnectionState) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.connectionState != state else { return }
            self.connectionState = state
        }
    }

    // MARK: - Message handling

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        // Any frame — strike, status, or keepalive — is proof the stream lives.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastMessageAt = Date()
            self.recyclingAfterSilence = false
            self.reconnectAttempt = 0
            if self.connectionState != .connected {
                self.connectionState = .connected
            }
        }
        switch message {
        case .string(let text):
            parse(text)
        case .data(let data):
            // Live frames are LZW-compressed JSON; undecodable frames are
            // silently dropped (protocol may have changed — fail soft).
            if let text = LightningLZWDecoder.decode(data) {
                parse(text)
            }
        @unknown default:
            break
        }
    }

    private func parse(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let object = json as? [String: Any],
              let lat = object["lat"] as? Double,
              let lon = object["lon"] as? Double else {
            // Status/keepalive messages and anything unparseable are ignored.
            return
        }
        // "time" is epoch nanoseconds.
        let timeNumber = object["time"] as? NSNumber
        let date = timeNumber.map { Date(timeIntervalSince1970: $0.doubleValue / 1_000_000_000) } ?? Date()

        // Fully unparseable timestamps would break ordering; skip them.
        guard date <= Date().addingTimeInterval(60) else { return }

        let roundedLat = (lat * 1000).rounded() / 1000
        let roundedLon = (lon * 1000).rounded() / 1000

        let strike = LightningStrike(
            id: "\(Int(date.timeIntervalSince1970))-\(roundedLat)-\(roundedLon)",
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            date: date,
            polarity: (object["pol"] as? NSNumber)?.intValue,
            stationCount: (object["sig"] as? NSNumber)?.intValue
        )

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.strikes.append(strike)
            self.pruneExpired()
        }
    }

    // MARK: - Queries

    /// Distance in meters to the closest strike on record, or nil with no data.
    /// Call from the main thread (reads the published buffer).
    func nearestDistanceMeters(from coordinate: CLLocationCoordinate2D) -> CLLocationDistance? {
        guard !strikes.isEmpty else { return nil }
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return strikes.compactMap { strike in
            origin.distance(from: CLLocation(latitude: strike.coordinate.latitude, longitude: strike.coordinate.longitude))
        }.min()
    }

    // MARK: - Retention

    private func startPruning() {
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.pruneExpired()
                self?.checkStaleness()
            }
        }
        pruneTimer = timer
        DispatchQueue.main.async {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func pruneExpired() {
        let cutoff = Date().addingTimeInterval(-retentionInterval)
        strikes.removeAll { $0.date < cutoff }
    }
}

// MARK: - LZW decoding
//
// Swift port of the community decoder for Blitzortung's obfuscated frames
// (an LZW variant over raw bytes). Input bytes are treated as character
// codes; codes ≥ 256 index dictionary entries built as we go.

enum LightningLZWDecoder {

    static func decode(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return nil }

        var dictionary: [Int: String] = [:]
        var output: [String] = []
        output.reserveCapacity(bytes.count)

        let first = scalar(bytes[0])
        output.append(first)
        var previous = first
        var nextCode = 256

        for index in 1..<bytes.count {
            let code = Int(bytes[index])
            let entry: String
            if code < 256 {
                entry = scalar(bytes[index])
            } else if let stored = dictionary[code] {
                entry = stored
            } else {
                // The classic LZW "KwKwK" case.
                entry = previous + String(previous.prefix(1))
            }

            output.append(entry)
            dictionary[nextCode] = previous + String(entry.prefix(1))
            nextCode += 1
            previous = entry
        }

        return output.joined()
    }

    /// The reference decoder treats input as characters, not bytes. Bytes
    /// ≥ 128 must map to the same Unicode scalars the encoder used
    /// (Latin-1 semantics), so JSON text round-trips byte-for-byte.
    private static func scalar(_ byte: UInt8) -> String {
        String(bytes: [byte], encoding: .isoLatin1) ?? "?"
    }
}

// MARK: - Debug support

#if DEBUG
extension LightningService {
    /// Inject synthetic strikes around a coordinate so the radar layer can be
    /// exercised without a storm overhead.
    func injectSampleStrikes(around coordinate: CLLocationCoordinate2D, count: Int = 12) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let now = Date()
            for index in 0..<count {
                let offsetLat = Double.random(in: -0.35...0.35)
                let offsetLon = Double.random(in: -0.35...0.35)
                let age = Double.random(in: 0...(self.retentionInterval / 2))
                let date = now.addingTimeInterval(-age)
                let strike = LightningStrike(
                    id: "debug-\(index)-\(Int(date.timeIntervalSince1970))",
                    coordinate: CLLocationCoordinate2D(
                        latitude: coordinate.latitude + offsetLat,
                        longitude: coordinate.longitude + offsetLon
                    ),
                    date: date,
                    polarity: [-1, 1].randomElement(),
                    stationCount: Int.random(in: 3...15)
                )
                self.strikes.append(strike)
            }
        }
    }

    func clearSampleStrikes() {
        DispatchQueue.main.async { [weak self] in
            self?.strikes.removeAll { $0.id.hasPrefix("debug-") }
        }
    }
}
#endif
