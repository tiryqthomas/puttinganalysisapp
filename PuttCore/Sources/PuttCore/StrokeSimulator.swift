import Foundation

/// Produces realistic-looking watch motion for putting strokes, so the
/// detector can be tested and the iPhone app can be tried without a watch.
///
/// The arm angle follows a smooth pendulum: a half-cosine takeaway, a
/// quarter-cosine downswing that reaches peak speed exactly at impact, and
/// a quarter-sine follow-through that starts at that same speed.
public struct StrokeSimulator {
    public struct Stroke: Sendable, Equatable {
        public var backswingAngle: Double
        public var backswingTime: TimeInterval
        public var downswingTime: TimeInterval
        /// Follow-through angle ÷ backswing angle.
        public var throughRatio: Double

        public init(backswingAngle: Double, backswingTime: TimeInterval = 0.62, downswingTime: TimeInterval = 0.31, throughRatio: Double = 1.2) {
            self.backswingAngle = backswingAngle
            self.backswingTime = backswingTime
            self.downswingTime = downswingTime
            self.throughRatio = throughRatio
        }

        public var throughAngle: Double { backswingAngle * throughRatio }
        /// Keeps speed continuous through impact.
        public var throughTime: TimeInterval { throughRatio * downswingTime }
        public var impactAngularSpeed: Double { backswingAngle * .pi / (2 * downswingTime) }
    }

    public var sampleRate: Double = 100
    /// Gyroscope noise, rad/s (one standard deviation).
    public var noise: Double = 0.02
    /// The rotation axis in the watch frame. Any direction works.
    public var axis = Vector3(0.25, 0.92, 0.30).normalized
    private var rng: SeededGenerator

    public init(seed: UInt64 = 1) {
        rng = SeededGenerator(seed: seed)
    }

    /// Samples for one stroke, with stillness before and after.
    public mutating func samples(for stroke: Stroke, startingAt t0: TimeInterval = 0, stillBefore: TimeInterval = 0.8, stillAfter: TimeInterval = 0.8) -> [MotionSample] {
        let dt = 1 / sampleRate
        let A = stroke.backswingAngle, F = stroke.throughAngle
        let tb = stroke.backswingTime, td = stroke.downswingTime, tf = stroke.throughTime
        let total = stillBefore + tb + td + tf + stillAfter
        let n = Int(total * sampleRate)

        // Off-axis wobble direction, perpendicular to the main axis.
        let side = Vector3(axis.y, -axis.x, 0).normalized

        var out: [MotionSample] = []
        out.reserveCapacity(n)
        for k in 0..<n {
            let t = Double(k) * dt
            let u = t - stillBefore
            var w = 0.0  // angular speed about the stroke axis
            if u >= 0 && u < tb {
                w = A * .pi / (2 * tb) * sin(.pi * u / tb)
            } else if u >= tb && u < tb + td {
                w = -A * .pi / (2 * td) * sin(.pi / 2 * (u - tb) / td)
            } else if u >= tb + td && u < tb + td + tf {
                w = -F * .pi / (2 * tf) * cos(.pi / 2 * (u - tb - td) / tf)
            }
            let wobble = 0.08 * w * sin(7 * t)
            let rate = axis * (w + gauss() * noise) + side * (wobble + gauss() * noise) + Vector3(0, 0, gauss() * noise * 0.5)
            out.append(MotionSample(t: t0 + t, rotationRate: rate))
        }
        return out
    }

    /// A believable practice session: strokes of mixed length with a little
    /// natural variation in tempo and proportion, plus how far each rolled.
    ///
    /// `greenFactor` is metres of roll per square metre of backswing; about
    /// 60 is a medium-speed green.
    public mutating func session(count: Int, greenFactor: Double = 60, geometry: StrokeGeometry = StrokeGeometry()) -> [(stroke: Stroke, distance: Double)] {
        (0..<count).map { _ in
            let length = Double.random(in: 0.08...0.30, using: &rng)  // putter-head backswing, m
            let tempo = 2.0 * (1 + 0.06 * gauss())
            let downswing = 0.30 * (1 + 0.04 * gauss())
            let stroke = Stroke(
                backswingAngle: geometry.angle(forLength: length),
                backswingTime: downswing * tempo,
                downswingTime: downswing,
                throughRatio: 1.2 * (1 + 0.08 * gauss())
            )
            let distance = greenFactor * length * length * (1 + 0.08 * gauss())
            return (stroke, distance)
        }
    }

    private mutating func gauss() -> Double {
        let u1 = max(Double.random(in: 0..<1, using: &rng), 1e-12)
        let u2 = Double.random(in: 0..<1, using: &rng)
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

/// SplitMix64, so simulated sessions are repeatable in tests.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
