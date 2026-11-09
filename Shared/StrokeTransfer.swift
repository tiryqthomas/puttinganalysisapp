import Foundation
import PuttCore

/// The messages the watch and phone exchange over WatchConnectivity.
///
/// Strokes go watch → phone with `transferUserInfo`, which queues and
/// delivers in order even if the other app isn't running. Roll distances go
/// both ways the same way, so a roll entered on either device shows on the
/// other. Settings and the stroke chart go phone → watch with
/// `updateApplicationContext`, where only the latest value matters.
enum StrokeTransfer {
    static let strokeKey = "stroke"
    static let sessionKey = "sessionID"
    static let rollStrokeKey = "rollStrokeID"
    static let rollKey = "roll"
    static let stimpKey = "stimp"

    /// `stimp` is the green speed picked on the watch for this session.
    static func payload(for stroke: StrokeMetrics, sessionID: UUID, stimp: Double?) -> [String: Any] {
        let data = (try? JSONEncoder().encode(stroke)) ?? Data()
        var info: [String: Any] = [strokeKey: data, sessionKey: sessionID.uuidString]
        if let stimp { info[stimpKey] = stimp }
        return info
    }

    static func stroke(from userInfo: [String: Any]) -> (stroke: StrokeMetrics, sessionID: UUID?, stimp: Double?)? {
        guard let data = userInfo[strokeKey] as? Data,
              let stroke = try? JSONDecoder().decode(StrokeMetrics.self, from: data) else { return nil }
        let session = (userInfo[sessionKey] as? String).flatMap(UUID.init(uuidString:))
        return (stroke, session, userInfo[stimpKey] as? Double)
    }

    /// A roll distance for a stroke, in metres. `nil` clears it, which marks
    /// the stroke as a practice swing.
    static func payload(roll metres: Double?, strokeID: UUID) -> [String: Any] {
        [rollStrokeKey: strokeID.uuidString, rollKey: metres ?? -1]
    }

    static func roll(from userInfo: [String: Any]) -> (strokeID: UUID, metres: Double?)? {
        guard let id = (userInfo[rollStrokeKey] as? String).flatMap(UUID.init(uuidString:)),
              let value = userInfo[rollKey] as? Double else { return nil }
        return (id, value > 0 ? value : nil)
    }
}

/// Settings the phone owns and shares with the watch.
struct SharedSettings: Codable, Equatable {
    var pivotToHead: Double = 1.1
    var usesMetric: Bool = Locale.current.measurementSystem == .metric
    var watchHaptics: Bool = true
    /// The player's stroke chart, so the watch can suggest a roll distance.
    var chart: SpeedChart?

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
