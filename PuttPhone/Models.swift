import Foundation
import PuttCore
import SwiftData

@Model
final class PracticeSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    /// Free text, e.g. "Club putting green, quick".
    var note: String = ""
    /// Green speed. A picked range stores that range's typical Stimp;
    /// `stimpIsExact` is true when the player typed the actual reading.
    var stimp: Double?
    var stimpIsExact: Bool = false
    @Relationship(deleteRule: .cascade, inverse: \PuttStroke.session)
    var strokes: [PuttStroke] = []

    init(id: UUID = UUID(), startedAt: Date = Date()) {
        self.id = id
        self.startedAt = startedAt
    }

    var orderedStrokes: [PuttStroke] { strokes.sorted { $0.recordedAt < $1.recordedAt } }

    var greenSpeed: GreenSpeed? { stimp.map(GreenSpeed.init(stimp:)) }

    /// "Fast (11–12)" or "Stimp 10.5", or nil when not set.
    var speedLabel: String? {
        guard let stimp else { return nil }
        if stimpIsExact { return String(format: "Stimp %.1f", stimp) }
        let s = GreenSpeed(stimp: stimp)
        return "\(s.shortTitle) (\(s.stimpRange))"
    }
}

@Model
final class PuttStroke {
    @Attribute(.unique) var id: UUID
    var recordedAt: Date
    var backswingAngle: Double
    var throughAngle: Double
    var backswingTime: Double
    var downswingTime: Double
    var throughTime: Double
    var impactAngularSpeed: Double
    var angleTrace: [Double]
    /// How far the ball rolled, in metres. Nil until the player enters it;
    /// strokes left without a distance count as practice swings.
    var distance: Double?
    /// True when the stroke came from the simulator rather than the watch.
    var simulated: Bool
    var session: PracticeSession?

    init(_ m: StrokeMetrics, simulated: Bool) {
        id = m.id
        recordedAt = m.recordedAt
        backswingAngle = m.backswingAngle
        throughAngle = m.throughAngle
        backswingTime = m.backswingTime
        downswingTime = m.downswingTime
        throughTime = m.throughTime
        impactAngularSpeed = m.impactAngularSpeed
        angleTrace = m.angleTrace
        self.simulated = simulated
    }

    var metrics: StrokeMetrics {
        StrokeMetrics(
            id: id,
            recordedAt: recordedAt,
            backswingAngle: backswingAngle,
            throughAngle: throughAngle,
            backswingTime: backswingTime,
            downswingTime: downswingTime,
            throughTime: throughTime,
            impactAngularSpeed: impactAngularSpeed,
            angleTrace: angleTrace
        )
    }

    func speedPoint(_ g: StrokeGeometry) -> SpeedPoint? {
        distance.map { SpeedPoint(backswing: g.length(forAngle: backswingAngle), distance: $0, stimp: session?.stimp) }
    }
}

extension Array where Element == PuttStroke {
    /// Consistency scores. Distance control compares each roll with the
    /// speed-adjusted stroke chart, so putts on different greens are fair.
    func report(geometry g: StrokeGeometry, chart: SpeedChart? = nil) -> ConsistencyReport {
        let points = compactMap { $0.speedPoint(g) }
        guard let chart else { return Consistency.report(strokes: map(\.metrics)) }
        return Consistency.report(
            strokes: map(\.metrics),
            distances: SpeedChart.normalized(points, usualStimp: chart.usualStimp),
            model: chart.combined
        )
    }

    func speedChart(geometry g: StrokeGeometry) -> SpeedChart? {
        SpeedChart(points: compactMap { $0.speedPoint(g) })
    }
}
