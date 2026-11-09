import Foundation

/// One stroke paired with how far the ball rolled.
public struct DistancePoint: Sendable, Codable, Equatable {
    /// Backswing length of the putter head, in metres.
    public var backswing: Double
    /// Roll distance, in metres.
    public var distance: Double

    public init(backswing: Double, distance: Double) {
        self.backswing = backswing
        self.distance = distance
    }
}

/// The player's personal "stroke chart": how far the ball rolls for a
/// given backswing, fitted from their own putts.
///
/// Rolling distance grows roughly with the square of ball speed, and with a
/// steady tempo ball speed grows with backswing length, so the fit is a
/// power law `distance = a · backswing^b`, solved as a straight line in
/// log–log space. `b` comes out near 2 for a pure pendulum stroke; the fit
/// leaves it free so it reflects how this player actually strokes it.
public struct DistanceModel: Sendable, Codable, Equatable {
    public var a: Double
    public var b: Double
    /// Goodness of fit in log space, 0...1.
    public var rSquared: Double
    public var pointCount: Int
    /// Range of backswings the fit was built from, in metres.
    public var backswingRange: ClosedRange<Double>

    public static let minimumPoints = 3

    public init?(points: [DistancePoint]) {
        let usable = points.filter { $0.backswing > 0.005 && $0.distance > 0.05 }
        guard usable.count >= Self.minimumPoints else { return nil }

        let xs = usable.map { log($0.backswing) }
        let ys = usable.map { log($0.distance) }
        let n = Double(usable.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        var sxx = 0.0, sxy = 0.0, syy = 0.0
        for (x, y) in zip(xs, ys) {
            sxx += (x - mx) * (x - mx)
            sxy += (x - mx) * (y - my)
            syy += (y - my) * (y - my)
        }
        // All backswings the same length: no slope to learn yet.
        guard sxx > 1e-6 else { return nil }

        b = sxy / sxx
        a = exp(my - b * mx)
        rSquared = syy > 0 ? min(1, max(0, (sxy * sxy) / (sxx * syy))) : 1
        pointCount = usable.count
        let backs = usable.map(\.backswing)
        backswingRange = backs.min()!...backs.max()!

        // A slope this flat or steep means the data is noise, not a stroke chart.
        guard b > 0.3, b < 5 else { return nil }
    }

    /// Expected roll, in metres, for a backswing in metres.
    public func distance(forBackswing backswing: Double) -> Double {
        guard backswing > 0 else { return 0 }
        return a * pow(backswing, b)
    }

    /// Backswing, in metres, expected to roll the ball `distance` metres.
    public func backswing(forDistance distance: Double) -> Double {
        guard distance > 0, a > 0, b > 0 else { return 0 }
        return pow(distance / a, 1 / b)
    }

    /// True when `backswing` lies inside the range of putts behind the fit,
    /// so the chart is interpolating rather than guessing.
    public func isSupported(backswing: Double) -> Bool {
        let pad = 0.15 * (backswingRange.upperBound - backswingRange.lowerBound)
        return backswing >= backswingRange.lowerBound - pad && backswing <= backswingRange.upperBound + pad
    }
}
