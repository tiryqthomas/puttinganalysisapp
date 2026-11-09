import Foundation

/// Turns a captured window of motion samples into stroke metrics.
///
/// How it works:
/// 1. A putting stroke is a pendulum, so the watch rotates mostly about a
///    single axis. That axis is the principal direction of the gyroscope
///    readings in the window.
/// 2. Projecting the gyroscope onto that axis gives a signed angular speed.
///    Integrating it gives the arm angle relative to address.
/// 3. The sign is chosen so the first movement (the takeaway) is positive.
///    The top of the backswing is the largest angle, impact is the moment
///    the angle comes back through zero, and the finish is the most
///    negative angle after impact.
public struct StrokeAnalyzer: Sendable {
    public struct Config: Sendable, Equatable {
        /// Shortest backswing counted as a stroke (radians). About 1.4°,
        /// roughly a 1 in (2.7 cm) putter-head backswing.
        public var minBackswingAngle: Double = 0.025
        /// The arm must travel past address by at least this much (radians).
        public var minThroughAngle: Double = 0.01
        public var backswingTimeRange: ClosedRange<Double> = 0.2...2.0
        public var downswingTimeRange: ClosedRange<Double> = 0.1...1.2
        /// The takeaway starts where angular speed rises above this fraction
        /// of the backswing's peak speed...
        public var takeawaySpeedFraction: Double = 0.05
        /// ...or above this floor (rad/s), whichever is larger, so sensor
        /// noise at address isn't mistaken for movement.
        public var takeawaySpeedFloor: Double = 0.02
        /// Moving-average width applied to the angular speed, in samples.
        public var smoothingWindow: Int = 5
        /// Points in `StrokeMetrics.angleTrace`.
        public var tracePoints: Int = 60

        public init() {}
    }

    public var config: Config

    public init(config: Config = Config()) {
        self.config = config
    }

    public enum Rejection: Error, Equatable {
        case tooFewSamples
        case noRotation
        case backswingTooShort
        case noImpact
        case timingOutOfRange
    }

    public func analyze(_ samples: [MotionSample], recordedAt: Date = Date()) -> Result<StrokeMetrics, Rejection> {
        guard samples.count >= 20 else { return .failure(.tooFewSamples) }

        let axis = Self.principalAxis(samples.map(\.rotationRate))
        guard axis.length > 0 else { return .failure(.noRotation) }

        var omega = Self.movingAverage(samples.map { $0.rotationRate.dot(axis) }, width: config.smoothingWindow)
        var theta = Self.integrate(omega, times: samples.map(\.t))

        // Make the takeaway positive: look at the first clear movement.
        let peakAbs = theta.map(abs).max() ?? 0
        guard peakAbs > 0 else { return .failure(.noRotation) }
        if let first = theta.first(where: { abs($0) > 0.25 * peakAbs }), first < 0 {
            omega = omega.map { -$0 }
            theta = theta.map { -$0 }
        }

        guard let iTop = theta.indices.max(by: { theta[$0] < theta[$1] }) else { return .failure(.noRotation) }
        let topAngle = theta[iTop]
        guard topAngle >= config.minBackswingAngle else { return .failure(.backswingTooShort) }

        // Takeaway: walk back from the top to where the arm was barely
        // moving. Using speed rather than angle finds the true onset of a
        // slow, smooth takeaway instead of clipping its first tenth.
        let iPeakBack = (0...iTop).max(by: { omega[$0] < omega[$1] }) ?? 0
        let onsetSpeed = max(config.takeawaySpeedFraction * omega[iPeakBack], config.takeawaySpeedFloor)
        var iStart = 0
        for i in stride(from: iPeakBack, through: 0, by: -1) where omega[i] <= onsetSpeed {
            iStart = i
            break
        }
        let tStart = Self.crossingTime(omega, samples, from: iStart, level: onsetSpeed)

        // Impact: first time after the top that the angle crosses zero.
        guard let iImpact = (iTop + 1..<theta.count).first(where: { theta[$0] <= 0 }) else {
            return .failure(.noImpact)
        }
        let tImpact = Self.crossingTime(theta, samples, from: iImpact - 1, level: 0)
        let impactSpeed = abs(Self.interpolate(omega, samples, at: tImpact, near: iImpact))

        // Finish: the most negative angle after impact.
        let after = iImpact..<theta.count
        guard let iFinish = after.min(by: { theta[$0] < theta[$1] }) else { return .failure(.noImpact) }
        let throughAngle = -theta[iFinish]
        guard throughAngle >= config.minThroughAngle else { return .failure(.noImpact) }

        let tTop = samples[iTop].t
        let backswingTime = tTop - tStart
        let downswingTime = tImpact - tTop
        let throughTime = max(0, samples[iFinish].t - tImpact)

        guard config.backswingTimeRange.contains(backswingTime),
              config.downswingTimeRange.contains(downswingTime) else {
            return .failure(.timingOutOfRange)
        }

        let trace = Self.resample(Array(theta[iStart...iFinish]), points: config.tracePoints)

        return .success(StrokeMetrics(
            recordedAt: recordedAt,
            backswingAngle: topAngle,
            throughAngle: throughAngle,
            backswingTime: backswingTime,
            downswingTime: downswingTime,
            throughTime: throughTime,
            impactAngularSpeed: impactSpeed,
            angleTrace: trace
        ))
    }

    // MARK: - Signal helpers

    /// Dominant rotation axis: the principal eigenvector of Σ ω ωᵀ, found by
    /// power iteration. Its sign is arbitrary.
    static func principalAxis(_ rates: [Vector3]) -> Vector3 {
        var m = [[Double]](repeating: [0, 0, 0], count: 3)
        for r in rates {
            let v = [r.x, r.y, r.z]
            for i in 0..<3 { for j in 0..<3 { m[i][j] += v[i] * v[j] } }
        }
        var v = [1.0, 1.0, 1.0]
        // Start from the largest-energy column so we never begin orthogonal to the answer.
        if let k = (0..<3).max(by: { m[$0][$0] < m[$1][$1] }) { v = m[k] }
        for _ in 0..<50 {
            var next = [0.0, 0.0, 0.0]
            for i in 0..<3 { for j in 0..<3 { next[i] += m[i][j] * v[j] } }
            let n = (next[0] * next[0] + next[1] * next[1] + next[2] * next[2]).squareRoot()
            guard n > 1e-12 else { return .zero }
            v = next.map { $0 / n }
        }
        return Vector3(v[0], v[1], v[2])
    }

    static func movingAverage(_ x: [Double], width: Int) -> [Double] {
        guard width > 1, x.count > width else { return x }
        let half = width / 2
        var out = [Double](repeating: 0, count: x.count)
        for i in x.indices {
            let lo = max(0, i - half), hi = min(x.count - 1, i + half)
            var s = 0.0
            for j in lo...hi { s += x[j] }
            out[i] = s / Double(hi - lo + 1)
        }
        return out
    }

    /// Trapezoidal integration, starting at zero.
    static func integrate(_ x: [Double], times: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: x.count)
        for i in 1..<x.count {
            out[i] = out[i - 1] + 0.5 * (x[i] + x[i - 1]) * (times[i] - times[i - 1])
        }
        return out
    }

    /// Time at which `y` crosses `level` between index `i` and `i + 1`.
    static func crossingTime(_ y: [Double], _ s: [MotionSample], from i: Int, level: Double) -> Double {
        guard i >= 0, i + 1 < y.count else { return s[max(0, min(i, s.count - 1))].t }
        let a = y[i] - level, b = y[i + 1] - level
        guard a != b else { return s[i].t }
        let f = min(max(a / (a - b), 0), 1)
        return s[i].t + f * (s[i + 1].t - s[i].t)
    }

    static func interpolate(_ y: [Double], _ s: [MotionSample], at t: Double, near i: Int) -> Double {
        let j = max(1, min(i, y.count - 1))
        let t0 = s[j - 1].t, t1 = s[j].t
        guard t1 > t0 else { return y[j] }
        let f = min(max((t - t0) / (t1 - t0), 0), 1)
        return y[j - 1] + f * (y[j] - y[j - 1])
    }

    static func resample(_ x: [Double], points: Int) -> [Double] {
        guard x.count > 1, points > 1 else { return x }
        return (0..<points).map { k in
            let pos = Double(k) * Double(x.count - 1) / Double(points - 1)
            let i = Int(pos), f = pos - Double(i)
            return i + 1 < x.count ? x[i] + f * (x[i + 1] - x[i]) : x[i]
        }
    }
}
