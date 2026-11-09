import Foundation
import PuttCore

/// The messages the watch and phone exchange over WatchConnectivity.
///
/// Strokes go watch → phone with `transferUserInfo`, which queues and
/// delivers even if the phone app isn't running. Settings go phone → watch
/// with `updateApplicationContext`, where only the latest value matters.
enum StrokeTransfer {
    static let strokeKey = "stroke"
    static let sessionKey = "sessionID"

    static func payload(for stroke: StrokeMetrics, sessionID: UUID) -> [String: Any] {
        let data = (try? JSONEncoder().encode(stroke)) ?? Data()
        return [strokeKey: data, sessionKey: sessionID.uuidString]
    }

    static func stroke(from userInfo: [String: Any]) -> (StrokeMetrics, UUID?)? {
        guard let data = userInfo[strokeKey] as? Data,
              let stroke = try? JSONDecoder().decode(StrokeMetrics.self, from: data) else { return nil }
        let session = (userInfo[sessionKey] as? String).flatMap(UUID.init(uuidString:))
        return (stroke, session)
    }
}

/// Settings the phone owns and shares with the watch.
struct SharedSettings: Codable, Equatable {
    var pivotToHead: Double = 1.1
    var usesMetric: Bool = Locale.current.measurementSystem == .metric
    var watchHaptics: Bool = true

    static let contextKey = "settings"

    var geometry: StrokeGeometry { StrokeGeometry(pivotToHead: pivotToHead) }

    var context: [String: Any] {
        [Self.contextKey: (try? JSONEncoder().encode(self)) ?? Data()]
    }

    init() {}

    init?(context: [String: Any]) {
        guard let data = context[Self.contextKey] as? Data,
              let s = try? JSONDecoder().decode(SharedSettings.self, from: data) else { return nil }
        self = s
    }
}

/// Formats stroke lengths and roll distances in the player's units.
struct Units {
    var metric: Bool

    /// Putter-head length, from metres.
    func length(_ metres: Double, decimals: Int = 1) -> String {
        metric
            ? String(format: "%.\(decimals)f cm", metres * 100)
            : String(format: "%.\(decimals)f in", metres / 0.0254)
    }

    func lengthValue(_ metres: Double) -> Double { metric ? metres * 100 : metres / 0.0254 }
    var lengthUnit: String { metric ? "cm" : "in" }

    /// Roll distance, from metres.
    func distance(_ metres: Double, decimals: Int = 0) -> String {
        metric
            ? String(format: "%.\(max(decimals, 1))f m", metres)
            : String(format: "%.\(decimals)f ft", metres / 0.3048)
    }

    func distanceValue(_ metres: Double) -> Double { metric ? metres : metres / 0.3048 }
    func metres(fromDistanceValue v: Double) -> Double { metric ? v : v * 0.3048 }
    var distanceUnit: String { metric ? "m" : "ft" }

    static func tempo(_ ratio: Double) -> String { String(format: "%.1f : 1", ratio) }
}
