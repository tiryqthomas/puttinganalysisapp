import Foundation
import PuttCore
import SwiftData

@Model
final class PracticeSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    /// Free text, e.g. "Club putting green, quick".
    var note: String = ""
    @Relationship(deleteRule: .cascade, inverse: \PuttStroke.session)
    var strokes: [PuttStroke] = []

    init(id: UUID = UUID(), startedAt: Date = Date()) {
        self.id = id
        self.startedAt = startedAt
    }

    var orderedStrokes: [PuttStroke] { strokes.sorted { $0.recordedAt < $1.recordedAt } }
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

    func distancePoint(_ g: StrokeGeometry) -> DistancePoint? {
        distance.map { DistancePoint(backswing: g.length(forAngle: backswingAngle), distance: $0) }
    }
}

extension Array where Element == PuttStroke {
    func report(geometry g: StrokeGeometry, model: DistanceModel? = nil) -> ConsistencyReport {
        Consistency.report(strokes: map(\.metrics), distances: compactMap { $0.distancePoint(g) }, model: model)
    }

    func distanceModel(geometry g: StrokeGeometry) -> DistanceModel? {
        DistanceModel(points: compactMap { $0.distancePoint(g) })
    }
}
