import Foundation

/// Watches a live motion stream and reports each completed putting stroke.
///
/// A stroke is captured when the wrist has been still at address, then
/// moves, then is still again. The captured window goes to
/// `StrokeAnalyzer`; anything it rejects (a waggle, a practice wave,
/// picking the ball up) is dropped.
///
/// Feed it samples in time order from one thread. It does no threading of
/// its own.
public final class StrokeDetector {
    public struct Config: Sendable, Equatable {
        /// Below this angular speed (rad/s) the wrist counts as still.
        public var stillSpeed: Double = 0.07
        /// Above this angular speed (rad/s) a stroke has started. Short
        /// putts are slow: a 3 ft putt peaks around 0.12 rad/s at the wrist.
        public var moveSpeed: Double = 0.09
        /// Smoothing applied to the gyroscope before those thresholds, as an
        /// exponential-average weight per sample (lower is smoother).
        public var speedSmoothing: Double = 0.2
        /// Stillness needed at address before a stroke can start.
        public var addressHold: TimeInterval = 0.35
        /// Stillness that ends a stroke.
        public var finishHold: TimeInterval = 0.3
        /// Longest a stroke can last before it's abandoned.
        public var maxStrokeDuration: TimeInterval = 4.0
        /// Samples kept from before the movement started.
        public var preRoll: TimeInterval = 0.3
        /// Time after a stroke before the next one can be armed.
        public var cooldown: TimeInterval = 0.8

        public init() {}
    }

    public enum Event {
        case stroke(StrokeMetrics, samples: [MotionSample])
        case rejected(StrokeAnalyzer.Rejection)
    }

    public enum Phase: Equatable {
        case settling   // waiting for the player to hold still at address
        case ready      // still at address; the next movement starts a stroke
        case capturing
    }

    public var config: Config
    public var analyzer: StrokeAnalyzer
    public private(set) var phase: Phase = .settling

    private var history: [MotionSample] = []
    private var capture: [MotionSample] = []
    private var stillSince: TimeInterval?
    private var captureStart: TimeInterval = 0
    private var cooldownUntil: TimeInterval = -.infinity
    private var smoothedRate: Vector3 = .zero

    public init(config: Config = Config(), analyzer: StrokeAnalyzer = StrokeAnalyzer()) {
        self.config = config
        self.analyzer = analyzer
    }

    public func reset() {
        phase = .settling
        history.removeAll()
        capture.removeAll()
        stillSince = nil
        cooldownUntil = -.infinity
        smoothedRate = .zero
    }

    /// Adds one sample. Returns an event when a stroke finishes.
    @discardableResult
    public func add(_ s: MotionSample) -> Event? {
        smoothedRate = smoothedRate * (1 - config.speedSmoothing) + s.rotationRate * config.speedSmoothing
        let speed = smoothedRate.length
        if speed < config.stillSpeed {
            if stillSince == nil { stillSince = s.t }
        } else {
            stillSince = nil
        }
        let stillFor = stillSince.map { s.t - $0 } ?? 0

        switch phase {
        case .settling, .ready:
            history.append(s)
            trimHistory(now: s.t)
            if phase == .settling, stillFor >= config.addressHold, s.t >= cooldownUntil {
                phase = .ready
            }
            if phase == .ready, speed > config.moveSpeed {
                phase = .capturing
                capture = history
                captureStart = s.t
                history.removeAll()
            }
            return nil

        case .capturing:
            capture.append(s)
            if stillFor >= config.finishHold {
                let window = capture
                capture.removeAll()
                // Hold off re-arming briefly so walking away from a held
                // finish isn't mistaken for the next takeaway.
                phase = .settling
                cooldownUntil = s.t + config.cooldown
                switch analyzer.analyze(window, recordedAt: Date()) {
                case .success(let m): return .stroke(m, samples: window)
                case .failure(let r): return .rejected(r)
                }
            }
            if s.t - captureStart > config.maxStrokeDuration {
                capture.removeAll()
                phase = .settling
                return .rejected(.timingOutOfRange)
            }
            return nil
        }
    }

    private func trimHistory(now: TimeInterval) {
        if let keepFrom = history.firstIndex(where: { now - $0.t <= config.preRoll }), keepFrom > 0 {
            history.removeFirst(keepFrom)
        }
    }
}
