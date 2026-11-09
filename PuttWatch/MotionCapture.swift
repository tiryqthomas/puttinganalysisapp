import CoreMotion
import Foundation
import PuttCore

/// Streams device motion at 100 Hz into a `StrokeDetector`.
///
/// Detection runs on a private serial queue; events are handed back on the
/// main queue.
final class MotionCapture {
    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInteractive
        q.name = "MotionCapture"
        return q
    }()
    private let detector = StrokeDetector()
    private var lastPhase: StrokeDetector.Phase = .settling

    var onEvent: ((StrokeDetector.Event) -> Void)?
    var onPhaseChange: ((StrokeDetector.Phase) -> Void)?

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        queue.addOperation { [detector] in detector.reset() }
        manager.deviceMotionUpdateInterval = 1.0 / 100.0
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            let sample = MotionSample(
                t: m.timestamp,
                rotationRate: Vector3(m.rotationRate.x, m.rotationRate.y, m.rotationRate.z),
                gravity: Vector3(m.gravity.x, m.gravity.y, m.gravity.z),
                userAcceleration: Vector3(m.userAcceleration.x, m.userAcceleration.y, m.userAcceleration.z)
            )
            let event = self.detector.add(sample)
            let phase = self.detector.phase
            let phaseChanged = phase != self.lastPhase
            self.lastPhase = phase
            if event != nil || phaseChanged {
                DispatchQueue.main.async {
                    if phaseChanged { self.onPhaseChange?(phase) }
                    if let event { self.onEvent?(event) }
                }
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
