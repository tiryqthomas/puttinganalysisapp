import Foundation
import Observation
import PuttCore
import WatchConnectivity
import WatchKit

/// State for one practice session on the watch.
@Observable
final class PracticeModel: NSObject, WCSessionDelegate {
    /// One model for the app, so the app delegate can start a session
    /// when the phone opens the app.
    static let shared = PracticeModel()

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
    /// Roll distances in metres, by stroke. Entered here or on the phone.
    private(set) var rolls: [UUID: Double] = [:]
    /// Optional landmarks noted with a roll, by stroke.
    private(set) var landmarks: [UUID: Landmark] = [:]

    @ObservationIgnored private let motion = MotionCapture()
    @ObservationIgnored private let workout = WorkoutKeeper()

    var isRunning: Bool { status != .idle }
    var latest: StrokeMetrics? { strokes.last }
    var units: Units { Units(metric: settings.usesMetric) }
    /// Green speed for this session, picked before Start. Remembered for
    /// next time, since players often practice on the same green.
    var greenSpeed: GreenSpeed? {
        didSet { UserDefaults.standard.set(greenSpeed?.rawValue, forKey: "greenSpeed") }
    }

    var report: ConsistencyReport {
        let g = settings.geometry
        let points = strokes.compactMap { m in
            rolls[m.id].map { SpeedPoint(backswing: g.length(forAngle: m.backswingAngle), distance: $0, stimp: greenSpeed?.typicalStimp) }
        }
        guard let chart = settings.chart else { return Consistency.report(strokes: strokes) }
        return Consistency.report(strokes: strokes,
                                  distances: SpeedChart.normalized(points, usualStimp: chart.usualStimp),
                                  model: chart.combined)
    }

    /// Starting value for the roll picker: what the stroke chart predicts for
    /// this backswing, else the last roll entered, else 3 paces.
    func suggestedRoll(for m: StrokeMetrics) -> Double {
        let back = settings.geometry.length(forAngle: m.backswingAngle)
        if let chart = settings.chart {
            let stimp = greenSpeed?.typicalStimp ?? chart.usualStimp
            if chart.isSupported(backswing: back, stimp: stimp) {
                return chart.distance(forBackswing: back, stimp: stimp)
            }
        }
        if let last = strokes.last(where: { rolls[$0.id] != nil }).flatMap({ rolls[$0.id] }) {
            return last
        }
        return units.metres(fromDistanceValue: 3)
    }

    /// Records how far the ball rolled for a stroke (nil for a practice
    /// swing), with the landmark if the player noted one, and sends it to
    /// the phone.
    func setRoll(_ metres: Double?, landmark: Landmark? = nil, for id: UUID) {
        rolls[id] = metres
        landmarks[id] = metres == nil ? nil : landmark
        if WCSession.default.activationState == .activated {
            WCSession.default.transferUserInfo(StrokeTransfer.payload(roll: metres, landmark: landmarks[id], strokeID: id))
        }
    }

    override init() {
        super.init()
        greenSpeed = UserDefaults.standard.string(forKey: "greenSpeed").flatMap(GreenSpeed.init(rawValue:))
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

    /// `sessionID` is set when the phone started the session, so its strokes
    /// land in the session the phone already made.
    func start(sessionID id: UUID? = nil) {
        guard !isRunning else { return }
        strokes = []
        rolls = [:]
        landmarks = [:]
        sessionID = id ?? UUID()
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
        if !strokes.isEmpty, WCSession.default.activationState == .activated {
            WCSession.default.transferUserInfo(StrokeTransfer.endPayload(sessionID: sessionID))
        }
        if settings.watchHaptics { WKInterfaceDevice.current().play(.stop) }
    }

    private func handle(_ event: StrokeDetector.Event) {
        switch event {
        case .stroke(let m, _):
            strokes.append(m)
            lastRejected = nil
            if settings.watchHaptics { WKInterfaceDevice.current().play(.success) }
            if WCSession.default.activationState == .activated {
                WCSession.default.transferUserInfo(StrokeTransfer.payload(for: m, sessionID: sessionID, stimp: greenSpeed?.typicalStimp))
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

    /// The phone asked to start a session. The watch app may already be
    /// running it, if the phone launched it with a workout first; then it
    /// just takes the phone's session ID and green speed.
    func applyStart(sessionID id: UUID, stimp: Double?) {
        if let stimp { greenSpeed = GreenSpeed(stimp: stimp) }
        if !isRunning {
            start(sessionID: id)
        } else if strokes.isEmpty {
            sessionID = id
        }
    }

    /// A roll entered on the phone, or a start request.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleMessage(userInfo)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleMessage(message)
    }

    private func handleMessage(_ info: [String: Any]) {
        if let start = StrokeTransfer.start(from: info) {
            DispatchQueue.main.async { self.applyStart(sessionID: start.sessionID, stimp: start.stimp) }
            return
        }
        guard let roll = StrokeTransfer.roll(from: info) else { return }
        DispatchQueue.main.async {
            self.rolls[roll.strokeID] = roll.metres
            self.landmarks[roll.strokeID] = roll.landmark
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        if let s = SharedSettings(context: context) {
            DispatchQueue.main.async { self.settings = s }
        }
    }
}
