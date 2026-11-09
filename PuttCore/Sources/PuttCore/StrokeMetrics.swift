import Foundation

/// What one putting stroke measured.
///
/// Angles are how far the lead arm (and the watch on it) rotated, in
/// radians. Turning an angle into a putter-head distance needs the
/// distance from the pivot (roughly the base of the neck) to the putter
/// head, which `StrokeGeometry` holds so the player can calibrate it.
public struct StrokeMetrics: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var recordedAt: Date

    /// Arm rotation from address to the top of the backswing.
    public var backswingAngle: Double
    /// Arm rotation from impact to the end of the follow-through.
    public var throughAngle: Double

    /// Takeaway to top of backswing.
    public var backswingTime: TimeInterval
    /// Top of backswing to impact.
    public var downswingTime: TimeInterval
    /// Impact to end of follow-through.
    public var throughTime: TimeInterval

    /// Arm angular speed when the putter returns to address (rad/s).
    public var impactAngularSpeed: Double

    /// The arm angle over the stroke, resampled to a fixed number of
    /// points, for drawing the stroke shape. Positive is backswing.
    public var angleTrace: [Double]

    public init(
        id: UUID = UUID(),
        recordedAt: Date = Date(),
        backswingAngle: Double,
        throughAngle: Double,
        backswingTime: TimeInterval,
        downswingTime: TimeInterval,
        throughTime: TimeInterval,
        impactAngularSpeed: Double,
        angleTrace: [Double] = []
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.backswingAngle = backswingAngle
        self.throughAngle = throughAngle
        self.backswingTime = backswingTime
        self.downswingTime = downswingTime
        self.throughTime = throughTime
        self.impactAngularSpeed = impactAngularSpeed
        self.angleTrace = angleTrace
    }

    /// Backswing time divided by downswing time. Good putters tend to sit
    /// near 2.0 and, more importantly, keep it the same for every length.
    public var tempoRatio: Double { downswingTime > 0 ? backswingTime / downswingTime : 0 }

    /// Takeaway to impact.
    public var strokeTime: TimeInterval { backswingTime + downswingTime }

    /// Follow-through length relative to backswing length.
    public var throughToBackRatio: Double { backswingAngle > 0 ? throughAngle / backswingAngle : 0 }
}

/// Converts arm rotation into putter-head travel.
public struct StrokeGeometry: Sendable, Codable, Equatable {
    /// Distance from the stroke's pivot point to the putter head, in metres.
    /// For most adults with a standard 33–35 in putter this is about 1.1 m.
    public var pivotToHead: Double

    public init(pivotToHead: Double = 1.1) {
        self.pivotToHead = pivotToHead
    }

    /// Putter-head arc length for an arm rotation, in metres.
    public func length(forAngle angle: Double) -> Double { angle * pivotToHead }

    /// Arm rotation needed for a putter-head arc length in metres.
    public func angle(forLength length: Double) -> Double { pivotToHead > 0 ? length / pivotToHead : 0 }

    /// Putter-head speed at impact, in m/s.
    public func headSpeed(for stroke: StrokeMetrics) -> Double { stroke.impactAngularSpeed * pivotToHead }

    /// Calibrates `pivotToHead` from one stroke whose backswing the player
    /// measured (for example against a ruler or alignment stick).
    public static func calibrated(from stroke: StrokeMetrics, measuredBackswing metres: Double) -> StrokeGeometry? {
        guard stroke.backswingAngle > 0.01, metres > 0 else { return nil }
        return StrokeGeometry(pivotToHead: metres / stroke.backswingAngle)
    }
}
