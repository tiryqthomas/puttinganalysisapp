import Foundation

/// How fast a green is, as the ranges players use day to day.
///
/// A Stimpmeter rolls a ball onto the green at a fixed starting speed and
/// measures how far it goes, in feet. So the same stroke rolls roughly in
/// proportion to the Stimp reading: a putt that rolls 16 ft on an 8 rolls
/// about 22 ft on an 11.
public enum GreenSpeed: String, Codable, CaseIterable, Sendable, Identifiable {
    case verySlow
    case slow
    case fast
    case veryFast

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .verySlow: "Very slow"
        case .slow: "Slow to medium"
        case .fast: "Medium-fast to fast"
        case .veryFast: "Very fast"
        }
    }

    /// Short label for tight spaces, like a segmented control or the watch.
    public var shortTitle: String {
        switch self {
        case .verySlow: "Very slow"
        case .slow: "Slow"
        case .fast: "Fast"
        case .veryFast: "Very fast"
        }
    }

    public var stimpRange: String {
        switch self {
        case .verySlow: "under 7"
        case .slow: "7–9"
        case .fast: "10–12"
        case .veryFast: "13+"
        }
    }

    /// Where it's usually found, to help a player pick.
    public var example: String {
        switch self {
        case .verySlow: "Shaggy practice greens, winter, wet days"
        case .slow: "Most public courses"
        case .fast: "Well-kept private clubs, tournament prep"
        case .veryFast: "Tour events, firm summer greens"
        }
    }

    /// The Stimp used for this range when the exact number isn't known.
    public var typicalStimp: Double {
        switch self {
        case .verySlow: 6
        case .slow: 8
        case .fast: 11
        case .veryFast: 13.5
        }
    }

    /// The range an exact Stimp reading falls in.
    public init(stimp: Double) {
        switch stimp {
        case ..<6.5: self = .verySlow
        case ..<9.5: self = .slow
        case ..<12.5: self = .fast
        default: self = .veryFast
        }
    }
}

/// A stroke paired with how far it rolled and how fast the green was.
public struct SpeedPoint: Sendable, Codable, Equatable {
    /// Putter-head backswing, metres.
    public var backswing: Double
    /// Roll distance, metres.
    public var distance: Double
    /// Stimp of the green, or nil when the player didn't say.
    public var stimp: Double?

    public init(backswing: Double, distance: Double, stimp: Double?) {
        self.backswing = backswing
        self.distance = distance
        self.stimp = stimp
    }
}

/// The stroke chart with green speed taken into account.
///
/// Every roll is first scaled to what it would have been on a reference
/// green (Stimp 10, or the player's usual speed when rolls have no speed),
/// using the rule that roll distance is proportional to Stimp. One curve is
/// fitted to all of those, so every putt helps every speed. A speed range
/// with enough putts of its own gets its own curve from just those putts,
/// which replaces the estimate for that range.
public struct SpeedChart: Sendable, Codable, Equatable {
    public static let referenceStimp = 10.0

    /// Fitted to all rolls scaled to `referenceStimp`.
    public var combined: DistanceModel
    /// Fitted to each range's own rolls, scaled to that range's typical Stimp.
    public var measured: [GreenSpeed: DistanceModel]
    /// Rolls logged per range (rolls with no speed aren't counted).
    public var counts: [GreenSpeed: Int]
    /// The speed most of the player's rolls were on, for "vs. usual".
    public var usualStimp: Double

    public init?(points: [SpeedPoint]) {
        let known = points.compactMap(\.stimp)
        let usual = known.isEmpty ? Self.referenceStimp : Self.median(known)
        let normalized = points.map {
            DistancePoint(backswing: $0.backswing, distance: $0.distance * Self.referenceStimp / ($0.stimp ?? usual))
        }
        guard let combined = DistanceModel(points: normalized) else { return nil }
        self.combined = combined
        self.usualStimp = usual

        var measured: [GreenSpeed: DistanceModel] = [:]
        var counts: [GreenSpeed: Int] = [:]
        for speed in GreenSpeed.allCases {
            let own = points.filter { $0.stimp.map(GreenSpeed.init(stimp:)) == speed }
            counts[speed] = own.count
            let scaled = own.map {
                DistancePoint(backswing: $0.backswing, distance: $0.distance * speed.typicalStimp / ($0.stimp ?? speed.typicalStimp))
            }
            if own.count >= Self.minimumOwnPoints, let m = DistanceModel(points: scaled) {
                measured[speed] = m
            }
        }
        self.measured = measured
        self.counts = counts
    }

    /// Putts a range needs before it gets its own curve.
    public static let minimumOwnPoints = 5

    /// True when this range's numbers come from putts on greens that fast,
    /// false when they're estimated from other speeds.
    public func isMeasured(_ speed: GreenSpeed) -> Bool { measured[speed] != nil }

    /// Expected roll, metres, for a backswing in metres on a green of `stimp`.
    public func distance(forBackswing backswing: Double, stimp: Double) -> Double {
        let speed = GreenSpeed(stimp: stimp)
        if let m = measured[speed] {
            return m.distance(forBackswing: backswing) * stimp / speed.typicalStimp
        }
        return combined.distance(forBackswing: backswing) * stimp / Self.referenceStimp
    }

    /// Backswing, metres, expected to roll `distance` metres on a green of `stimp`.
    public func backswing(forDistance distance: Double, stimp: Double) -> Double {
        let speed = GreenSpeed(stimp: stimp)
        if let m = measured[speed] {
            return m.backswing(forDistance: distance * speed.typicalStimp / stimp)
        }
        return combined.backswing(forDistance: distance * Self.referenceStimp / stimp)
    }

    /// Range of backswings behind the curve used at this speed.
    public func backswingRange(for speed: GreenSpeed) -> ClosedRange<Double> {
        (measured[speed] ?? combined).backswingRange
    }

    /// True when `backswing` lies inside the putts behind the curve used at
    /// this speed.
    public func isSupported(backswing: Double, stimp: Double) -> Bool {
        (measured[GreenSpeed(stimp: stimp)] ?? combined).isSupported(backswing: backswing)
    }

    /// Each roll scaled to the reference green, with the matching model, for
    /// scoring distance control fairly across speeds.
    public static func normalized(_ points: [SpeedPoint], usualStimp: Double) -> [DistancePoint] {
        points.map { DistancePoint(backswing: $0.backswing, distance: $0.distance * referenceStimp / ($0.stimp ?? usualStimp)) }
    }

    static func median(_ x: [Double]) -> Double {
        let s = x.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}
