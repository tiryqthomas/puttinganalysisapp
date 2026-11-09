import Foundation
import Observation
import PuttCore
import SwiftData
import WatchConnectivity

/// Player settings, saved on the phone and mirrored to the watch.
@Observable
final class AppSettings {
    var value: SharedSettings {
        didSet {
            save()
            push()
        }
    }

    private static let key = "sharedSettings"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let s = try? JSONDecoder().decode(SharedSettings.self, from: data) {
            value = s
        } else {
            value = SharedSettings()
        }
    }

    var units: Units { Units(metric: value.usesMetric) }
    var geometry: StrokeGeometry { value.geometry }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: Self.key)
    }

    func push() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext(value.context)
    }
}

/// Receives strokes from the watch and files them into sessions.
@MainActor
@Observable
final class StrokeInbox: NSObject, WCSessionDelegate {
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let settings: AppSettings

    init(context: ModelContext, settings: AppSettings) {
        self.context = context
        self.settings = settings
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Adds a stroke to the session with `sessionID`, creating it if needed.
    func add(_ m: StrokeMetrics, sessionID: UUID?, simulated: Bool) {
        let session = sessionID.flatMap(find) ?? currentOrNewSession(id: sessionID)
        let stroke = PuttStroke(m, simulated: simulated)
        context.insert(stroke)
        stroke.session = session
        try? context.save()
    }

    /// The most recent session if it started within the last two hours,
    /// otherwise a new one. Used for simulated strokes.
    func currentOrNewSession(id: UUID? = nil) -> PracticeSession {
        if id == nil {
            var d = FetchDescriptor<PracticeSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
            d.fetchLimit = 1
            if let latest = try? context.fetch(d).first, Date().timeIntervalSince(latest.startedAt) < 2 * 3600 {
                return latest
            }
        }
        let s = PracticeSession(id: id ?? UUID())
        context.insert(s)
        return s
    }

    /// A roll entered on the watch.
    private func applyRoll(_ metres: Double?, strokeID: UUID) {
        let d = FetchDescriptor<PuttStroke>(predicate: #Predicate { $0.id == strokeID })
        guard let stroke = try? context.fetch(d).first else { return }
        stroke.distance = metres
        try? context.save()
        refreshChart()
    }

    /// Call after a roll is entered or changed on the phone: tells the watch
    /// and refreshes the stroke chart it uses for suggestions.
    func rollChanged(_ stroke: PuttStroke) {
        if WCSession.isSupported(), WCSession.default.activationState == .activated, !stroke.simulated {
            WCSession.default.transferUserInfo(StrokeTransfer.payload(roll: stroke.distance, strokeID: stroke.id))
        }
        refreshChart()
    }

    /// Recomputes the stroke chart from every logged roll and shares it with
    /// the watch if it changed.
    func refreshChart() {
        let all = (try? context.fetch(FetchDescriptor<PuttStroke>())) ?? []
        let chart = all.distanceModel(geometry: settings.geometry)
        if settings.value.chart != chart {
            settings.value.chart = chart
        }
    }

    private func find(_ id: UUID) -> PracticeSession? {
        let d = FetchDescriptor<PracticeSession>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(d).first
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.refreshChart()
            self.settings.push()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let roll = StrokeTransfer.roll(from: userInfo) {
            Task { @MainActor in self.applyRoll(roll.metres, strokeID: roll.strokeID) }
            return
        }
        guard let decoded = StrokeTransfer.stroke(from: userInfo) else { return }
        let (stroke, sessionID) = decoded
        Task { @MainActor in self.add(stroke, sessionID: sessionID, simulated: false) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}

/// Makes strokes without a watch, for trying the app and for demos.
@MainActor
@Observable
final class StrokeFaker {
    @ObservationIgnored private var sim = StrokeSimulator(seed: UInt64(Date().timeIntervalSince1970))
    @ObservationIgnored private let analyzer = StrokeAnalyzer()

    /// Runs a simulated stroke through the real analyzer, so the numbers
    /// carry the same measurement error the watch would have. Also returns
    /// a plausible roll distance for that stroke.
    func stroke(geometry: StrokeGeometry) -> (StrokeMetrics, suggestedDistance: Double)? {
        guard let planned = sim.session(count: 1, geometry: geometry).first else { return nil }
        let samples = sim.samples(for: planned.stroke)
        guard case .success(let m) = analyzer.analyze(samples) else { return nil }
        return (m, planned.distance)
    }
}
