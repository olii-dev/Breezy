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

final class LightningService: ObservableObject {

    static let shared = LightningService()

    /// Strikes recorded within the retention window, oldest first.
    @Published private(set) var strikes: [LightningStrike] = []
    /// True while the websocket is connected (or trying to be).
    @Published private(set) var isConnected = false

    private let retentionInterval: TimeInterval = 30 * 60
    private let servers = ["wss://ws1.blitzortung.org", "wss://ws2.blitzortung.org", "wss://ws3.blitzortung.org"]

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var serverIndex = 0
    private var reconnectAttempt = 0
    private var shouldRun = false
    private var pruneTimer: Timer?

    private let queue = DispatchQueue(label: "Breezy.LightningService")

    private init() {}

    // MARK: - Lifecycle

    func start() {
        queue.async { [weak self] in
            guard let self, !self.shouldRun else { return }
            self.shouldRun = true
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
            DispatchQueue.main.async { self.isConnected = false }
        }
    }

    // MARK: - Connection

    private func connect() {
        guard shouldRun else { return }
        let server = servers[serverIndex % servers.count]
        guard let url = URL(string: server) else { return }

        let session = URLSession(configuration: .ephemeral)
        self.session = session
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()

        // Handshake: tells the server to start streaming strike messages.
        task.send(.string("{\"a\": 111}")) { [weak self] error in
            DispatchQueue.main.async {
                self?.isConnected = (error == nil)
            }
            if error != nil {
                self?.scheduleReconnect()
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
            DispatchQueue.main.async { self.isConnected = false }

            // Exponential backoff, capped at 30s.
            let delay = min(30.0, pow(2.0, Double(min(self.reconnectAttempt, 5))))
            self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.shouldRun else { return }
                self.connect()
            }
        }
    }

    // MARK: - Message handling

    private func handle(_ message: URLSessionWebSocketTask.Message) {
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
