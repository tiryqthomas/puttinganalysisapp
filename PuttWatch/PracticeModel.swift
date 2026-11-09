import Foundation
import Observation
import PuttCore
import WatchConnectivity
import WatchKit

/// State for one practice session on the watch.
@Observable
final class PracticeModel: NSObject, WCSessionDelegate {
    enum Status: Equatable {
        case idle
        case settling   // waiting for stillness at address
        case ready      // still; next movement is captured
        case capturing
    }

    private(set) var status: Status = .idle
    private(set) var strokes: [StrokeMetrics] = []
    private(set) var settings = SharedSettings()
    private(set) var sessionID = UUID()
    private(set) var sensorsAvailable = true
    /// Set when a movement was seen but didn't look like a stroke; cleared
    /// when the next movement starts.
    private(set) var lastRejected: Date?

    @ObservationIgnored private let motion = MotionCapture()
    @ObservationIgnored private let workout = WorkoutKeeper()

    var isRunning: Bool { status != .idle }
    var latest: StrokeMetrics? { strokes.last }
    var units: Units { Units(metric: settings.usesMetric) }
    var report: ConsistencyReport { Consistency.report(strokes: strokes) }

    override init() {
        super.init()
        sensorsAvailable = motion.isAvailable
        motion.onPhaseChange = { [weak self] phase in
            guard let self, self.isRunning else { return }
            switch phase {
            case .settling: self.status = .settling
            case .ready: self.status = .ready
            case .capturing:
                self.status = .capturing
                self.lastRejected = nil
            }
        }
        motion.onEvent = { [weak self] event in self?.handle(event) }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func start() {
        guard !isRunning else { return }
        strokes = []
        sessionID = UUID()
        lastRejected = nil
        status = .settling
        Task { await workout.start() }
        motion.start()
        if settings.watchHaptics { WKInterfaceDevice.current().play(.start) }
    }

    func stop() {
        guard isRunning else { return }
        motion.stop()
        workout.stop()
        status = .idle
        if settings.watchHaptics { WKInterfaceDevice.current().play(.stop) }
    }

    private func handle(_ event: StrokeDetector.Event) {
        switch event {
        case .stroke(let m, _):
            strokes.append(m)
            lastRejected = nil
            if settings.watchHaptics { WKInterfaceDevice.current().play(.success) }
            if WCSession.default.activationState == .activated {
                WCSession.default.transferUserInfo(StrokeTransfer.payload(for: m, sessionID: sessionID))
            }
        case .rejected:
            lastRejected = Date()
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        if let s = SharedSettings(context: session.receivedApplicationContext) {
            DispatchQueue.main.async { self.settings = s }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        if let s = SharedSettings(context: context) {
            DispatchQueue.main.async { self.settings = s }
        }
    }
}
