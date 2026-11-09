import Foundation

/// Where the putter head stopped at the top of the backswing, measured
/// against the player's own foot, relative to where the putter starts.
///
/// Players note one now and then when they save a roll. Over time each
/// landmark collects the backswings that ended there, so the app can say
/// "for 6 paces on fast greens, take it back to the middle of your foot".
public enum Landmark: Int, Codable, CaseIterable, Sendable, Identifiable {
    case inside = 0
    case insideMiddle
    case middle
    case outsideMiddle
    case outside

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .inside: "Inside"
        case .insideMiddle: "Inside-middle"
        case .middle: "Middle"
        case .outsideMiddle: "Outside-middle"
        case .outside: "Outside"
        }
    }

    /// Shown next to every landmark picker, so players mark it the same way each time.
    public static let explanation = "Relative to where the putter starts on your foot."
}

/// A backswing paired with the landmark the player noted for it.
public struct LandmarkPoint: Sendable, Codable, Equatable {
    /// Putter-head backswing, metres.
    public var backswing: Double
    public var landmark: Landmark
    /// Stimp of the green, or nil when the player didn't say.
    public var stimp: Double?

    public init(backswing: Double, landmark: Landmark, stimp: Double?) {
        self.backswing = backswing
        self.landmark = landmark
        self.stimp = stimp
    }
}

/// Which landmark each backswing length reaches, learned from the player's
/// own notes.
///
/// A landmark is a fixed spot on the foot, so it always means the same
/// backswing length whatever the green. What changes with green speed is
/// the backswing a distance needs: combine this with `SpeedChart` and the
/// landmark for "6 paces" moves toward the inside of the foot on faster
/// greens and toward the outside on slower ones.
public struct LandmarkMap: Sendable, Codable, Equatable {
    /// Typical backswing, metres, for each landmark the player has used.
    public var centers: [Landmark: Double]
    /// Notes per green speed (notes with no speed aren't counted).
    public var counts: [GreenSpeed: Int]
    public var pointCount: Int

    /// Nil until the player has noted at least one landmark.
    public init?(points: [LandmarkPoint]) {
        guard !points.isEmpty else { return nil }
        var centers: [Landmark: Double] = [:]
        for landmark in Landmark.allCases {
            let backs = points.filter { $0.landmark == landmark }.map(\.backswing)
            if !backs.isEmpty { centers[landmark] = SpeedChart.median(backs) }
        }
        var counts: [GreenSpeed: Int] = [:]
        for speed in GreenSpeed.allCases {
            counts[speed] = points.filter { $0.stimp.map(GreenSpeed.init(stimp:)) == speed }.count
        }
        self.centers = centers
        self.counts = counts
        self.pointCount = points.count
    }

    /// Notes at a speed before its landmarks count as measured rather than estimated.
    public static let minimumOwnPoints = 5

    /// The landmark whose typical backswing is closest to `backswing` (metres).
    /// Only landmarks the player has actually used are considered.
    public func landmark(forBackswing backswing: Double) -> Landmark {
        centers.min { abs($0.value - backswing) < abs($1.value - backswing) }!.key
    }

    /// The landmark to take the putter back to for a roll of `distance`
    /// metres on a green of `stimp`.
    public func landmark(forDistance distance: Double, stimp: Double, chart: SpeedChart) -> Landmark {
        landmark(forBackswing: chart.backswing(forDistance: distance, stimp: stimp))
    }

    /// True when there are enough notes on greens this fast and the stroke
    /// chart has its own curve for them.
    public func isMeasured(_ speed: GreenSpeed, chart: SpeedChart) -> Bool {
        (counts[speed] ?? 0) >= Self.minimumOwnPoints && chart.isMeasured(speed)
    }
}
