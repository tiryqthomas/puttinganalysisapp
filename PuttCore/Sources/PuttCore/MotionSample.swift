import Foundation

/// A 3D vector in the watch's device frame.
public struct Vector3: Sendable, Codable, Equatable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vector3(0, 0, 0)

    public var length: Double { (x * x + y * y + z * z).squareRoot() }

    public var normalized: Vector3 {
        let l = length
        return l > 0 ? Vector3(x / l, y / l, z / l) : .zero
    }

    public func dot(_ o: Vector3) -> Double { x * o.x + y * o.y + z * o.z }

    public static func + (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Vector3, b: Vector3) -> Vector3 { Vector3(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (a: Vector3, s: Double) -> Vector3 { Vector3(a.x * s, a.y * s, a.z * s) }
}

/// One reading from Core Motion's device-motion stream (`CMDeviceMotion`).
///
/// `rotationRate` is the bias-corrected gyroscope in rad/s. `gravity` and
/// `userAcceleration` are in g. Only `rotationRate` drives stroke detection
/// today; the other two are kept so logged sessions can be replayed later
/// with better algorithms (for example impact detection from the
/// acceleration spike when the putter meets the ball).
public struct MotionSample: Sendable, Codable, Equatable {
    public var t: TimeInterval
    public var rotationRate: Vector3
    public var gravity: Vector3
    public var userAcceleration: Vector3

    public init(t: TimeInterval, rotationRate: Vector3, gravity: Vector3 = Vector3(0, 0, -1), userAcceleration: Vector3 = .zero) {
        self.t = t
        self.rotationRate = rotationRate
        self.gravity = gravity
        self.userAcceleration = userAcceleration
    }
}
