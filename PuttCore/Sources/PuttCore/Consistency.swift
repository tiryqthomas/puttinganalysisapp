import Foundation

/// Consistency scores for a group of strokes (a session, or the last N).
///
/// Stroke length should change with distance, so length itself is not
/// scored. What should stay the same from a 5-footer to a 40-footer is:
/// - **Tempo**: backswing time ÷ downswing time.
/// - **Rhythm**: total time from takeaway to impact.
/// - **Proportion**: follow-through length ÷ backswing length.
/// - **Distance control**: how closely each roll matched what your own
///   stroke chart predicts for that backswing.
///
/// Each score is 0–100, where 100 means no variation.
public struct ConsistencyReport: Sendable, Equatable {
    public var strokeCount: Int
    public var tempo: Double?
    public var rhythm: Double?
    public var proportion: Double?
    public var distanceControl: Double?

    /// Average tempo ratio across the strokes.
    public var meanTempoRatio: Double?

    /// Mean of the scores that could be computed.
    public var overall: Double? {
        let parts = [tempo, rhythm, proportion, distanceControl].compactMap { $0 }
        return parts.isEmpty ? nil : parts.reduce(0, +) / Double(parts.count)
    }
}

public enum Consistency {
    /// Fewest strokes before variation-based scores mean anything.
    public static let minimumStrokes = 3

    /// Coefficient of variation at which each score reaches zero.
    public struct Scale: Sendable, Equatable {
        public var tempo = 0.25
        public var rhythm = 0.25
        public var proportion = 0.40
        /// Mean absolute error, as a fraction of the predicted distance.
        public var distance = 0.40
        public init() {}
    }

    public static func report(
        strokes: [StrokeMetrics],
        distances: [DistancePoint] = [],
        model: DistanceModel? = nil,
        scale: Scale = Scale()
    ) -> ConsistencyReport {
        var r = ConsistencyReport(strokeCount: strokes.count)
        if !strokes.isEmpty {
            r.meanTempoRatio = mean(strokes.map(\.tempoRatio))
        }
        if strokes.count >= minimumStrokes {
            r.tempo = score(cv: cv(strokes.map(\.tempoRatio)), zeroAt: scale.tempo)
            r.rhythm = score(cv: cv(strokes.map(\.strokeTime)), zeroAt: scale.rhythm)
            r.proportion = score(cv: cv(strokes.map(\.throughToBackRatio)), zeroAt: scale.proportion)
        }
        if let model = model ?? DistanceModel(points: distances), distances.count >= minimumStrokes + 1 {
            let errors = distances.compactMap { p -> Double? in
                let predicted = model.distance(forBackswing: p.backswing)
                return predicted > 0 ? abs(p.distance - predicted) / predicted : nil
            }
            if !errors.isEmpty {
                r.distanceControl = score(cv: mean(errors), zeroAt: scale.distance)
            }
        }
        return r
    }

    /// Where a score sits against the player's own recent sessions.
    public enum Placement: Sendable, Equatable {
        case below, within, above
    }

    /// Sessions a usual range needs before it means anything.
    public static let minimumSessionsForRange = 3

    /// The player's usual range for a score: the mean of their recent
    /// sessions, give or take one standard deviation, and never narrower
    /// than ±3 points so a single steady week doesn't make every session
    /// look unusual. Nil with fewer than `minimumSessionsForRange` scores.
    public static func usualRange(of scores: [Double]) -> ClosedRange<Double>? {
        guard scores.count >= minimumSessionsForRange else { return nil }
        let m = mean(scores)
        let sd = (scores.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(scores.count)).squareRoot()
        let half = max(sd, 3)
        return max(0, m - half)...min(100, m + half)
    }

    public static func placement(of score: Double, in range: ClosedRange<Double>) -> Placement {
        score < range.lowerBound ? .below : score > range.upperBound ? .above : .within
    }

    static func score(cv: Double, zeroAt: Double) -> Double {
        guard cv.isFinite, zeroAt > 0 else { return 0 }
        return min(100, max(0, 100 * (1 - cv / zeroAt)))
    }

    static func mean(_ x: [Double]) -> Double {
        x.isEmpty ? 0 : x.reduce(0, +) / Double(x.count)
    }

    /// Sample standard deviation over the mean.
    static func cv(_ x: [Double]) -> Double {
        guard x.count > 1 else { return 0 }
        let m = mean(x)
        guard abs(m) > 1e-9 else { return .infinity }
        let v = x.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(x.count - 1)
        return v.squareRoot() / abs(m)
    }
}
