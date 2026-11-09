import XCTest
@testable import PuttCore

final class StrokeDetectionTests: XCTestCase {
    private func detect(_ samples: [MotionSample]) -> (strokes: [StrokeMetrics], rejected: [StrokeAnalyzer.Rejection]) {
        let detector = StrokeDetector()
        var strokes: [StrokeMetrics] = []
        var rejected: [StrokeAnalyzer.Rejection] = []
        for s in samples {
            switch detector.add(s) {
            case .stroke(let m, _)?: strokes.append(m)
            case .rejected(let r)?: rejected.append(r)
            case nil: break
            }
        }
        return (strokes, rejected)
    }

    func testMeasuresAMediumStroke() throws {
        var sim = StrokeSimulator(seed: 42)
        let truth = StrokeSimulator.Stroke(backswingAngle: 0.15, backswingTime: 0.6, downswingTime: 0.3, throughRatio: 1.25)
        let result = detect(sim.samples(for: truth))
        let m = try XCTUnwrap(result.strokes.first)
        XCTAssertEqual(result.strokes.count, 1)
        XCTAssertEqual(m.backswingAngle, truth.backswingAngle, accuracy: truth.backswingAngle * 0.05)
        XCTAssertEqual(m.throughAngle, truth.throughAngle, accuracy: truth.throughAngle * 0.05)
        XCTAssertEqual(m.tempoRatio, 2.0, accuracy: 0.2)
        XCTAssertEqual(m.impactAngularSpeed, truth.impactAngularSpeed, accuracy: truth.impactAngularSpeed * 0.08)
        XCTAssertEqual(m.angleTrace.count, 60)
    }

    func testDetectsEveryStrokeInASession() {
        var sim = StrokeSimulator(seed: 7)
        let plan = sim.session(count: 25)
        var samples: [MotionSample] = []
        var t = 0.0
        for item in plan {
            let s = sim.samples(for: item.stroke, startingAt: t)
            samples += s
            t = (s.last?.t ?? t) + 0.01
        }
        let result = detect(samples)
        XCTAssertEqual(result.strokes.count, plan.count)
        XCTAssertTrue(result.rejected.isEmpty)
        for (m, item) in zip(result.strokes, plan) {
            XCTAssertEqual(m.backswingAngle, item.stroke.backswingAngle, accuracy: item.stroke.backswingAngle * 0.12)
            XCTAssertEqual(m.tempoRatio, item.stroke.backswingTime / item.stroke.downswingTime, accuracy: 0.4)
        }
    }

    func testTakeawayInEitherDirectionReadsAsBackswing() throws {
        var sim = StrokeSimulator(seed: 3)
        sim.axis = sim.axis * -1
        let m = try XCTUnwrap(detect(sim.samples(for: .init(backswingAngle: 0.12))).strokes.first)
        XCTAssertGreaterThan(m.backswingAngle, 0.1)
        XCTAssertGreaterThan(m.throughAngle, 0.1)
    }

    func testIgnoresStillness() {
        var sim = StrokeSimulator(seed: 9)
        // A "stroke" with no swing is just three seconds of sensor noise.
        let samples = sim.samples(for: .init(backswingAngle: 0.0001), stillBefore: 1.5, stillAfter: 1.5)
        XCTAssertTrue(detect(samples).strokes.isEmpty)
    }

    func testRejectsAWaggleThatNeverComesThrough() {
        // Takeaway and return to address only: no follow-through past zero.
        var samples: [MotionSample] = []
        let axis = Vector3(0, 1, 0)
        for k in 0..<300 {
            let t = Double(k) / 100
            var w = 0.0
            if t >= 1.0 && t < 1.5 { w = 0.4 * sin(.pi * (t - 1.0) / 0.5) }
            if t >= 1.5 && t < 2.0 { w = -0.4 * sin(.pi * (t - 1.5) / 0.5) * 0.9 }
            samples.append(MotionSample(t: t, rotationRate: axis * w))
        }
        XCTAssertTrue(detect(samples).strokes.isEmpty)
    }
}

final class DistanceModelTests: XCTestCase {
    func testRecoversASquareLaw() throws {
        let points = [0.08, 0.12, 0.16, 0.22, 0.28].map { DistancePoint(backswing: $0, distance: 60 * $0 * $0) }
        let model = try XCTUnwrap(DistanceModel(points: points))
        XCTAssertEqual(model.b, 2, accuracy: 0.01)
        XCTAssertEqual(model.distance(forBackswing: 0.2), 2.4, accuracy: 0.01)
        XCTAssertEqual(model.backswing(forDistance: 2.4), 0.2, accuracy: 0.001)
        XCTAssertEqual(model.rSquared, 1, accuracy: 1e-6)
    }

    func testNeedsThreeDistinctPoints() {
        XCTAssertNil(DistanceModel(points: [.init(backswing: 0.1, distance: 1), .init(backswing: 0.2, distance: 3)]))
        XCTAssertNil(DistanceModel(points: Array(repeating: .init(backswing: 0.1, distance: 1), count: 5)))
    }
}

final class ConsistencyTests: XCTestCase {
    private func stroke(back: Double, bt: Double, dt: Double, through: Double) -> StrokeMetrics {
        StrokeMetrics(backswingAngle: back, throughAngle: through, backswingTime: bt, downswingTime: dt, throughTime: dt, impactAngularSpeed: 1)
    }

    func testIdenticalTempoScoresPerfect() throws {
        // Different lengths, identical tempo, rhythm and proportion.
        let strokes = [0.05, 0.1, 0.2].map { stroke(back: $0, bt: 0.6, dt: 0.3, through: $0 * 1.2) }
        let r = Consistency.report(strokes: strokes)
        XCTAssertEqual(try XCTUnwrap(r.tempo), 100, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(r.rhythm), 100, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(r.proportion), 100, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(r.meanTempoRatio), 2, accuracy: 1e-9)
        XCTAssertNil(r.distanceControl)
    }

    func testErraticTempoScoresLower() throws {
        let steady = (0..<6).map { _ in stroke(back: 0.1, bt: 0.6, dt: 0.3, through: 0.12) }
        let erratic = [0.4, 0.8, 0.5, 0.9, 0.45, 0.7].map { stroke(back: 0.1, bt: $0, dt: 0.3, through: 0.12) }
        let a = try XCTUnwrap(Consistency.report(strokes: steady).tempo)
        let b = try XCTUnwrap(Consistency.report(strokes: erratic).tempo)
        XCTAssertGreaterThan(a, b)
        XCTAssertLessThan(b, 50)
    }

    func testNeedsThreeStrokes() {
        let r = Consistency.report(strokes: [stroke(back: 0.1, bt: 0.6, dt: 0.3, through: 0.12)])
        XCTAssertNil(r.tempo)
        XCTAssertNil(r.overall)
    }

    func testDistanceControl() throws {
        let exact = [0.08, 0.12, 0.16, 0.22, 0.28].map { DistancePoint(backswing: $0, distance: 60 * $0 * $0) }
        let r = Consistency.report(strokes: [], distances: exact)
        XCTAssertEqual(try XCTUnwrap(r.distanceControl), 100, accuracy: 0.01)
    }
}

final class GeometryTests: XCTestCase {
    func testCalibration() throws {
        let m = StrokeMetrics(backswingAngle: 0.2, throughAngle: 0.24, backswingTime: 0.6, downswingTime: 0.3, throughTime: 0.36, impactAngularSpeed: 1)
        let g = try XCTUnwrap(StrokeGeometry.calibrated(from: m, measuredBackswing: 0.24))
        XCTAssertEqual(g.pivotToHead, 1.2, accuracy: 1e-9)
        XCTAssertEqual(g.length(forAngle: 0.1), 0.12, accuracy: 1e-9)
    }
}

final class GreenSpeedTests: XCTestCase {
    func testRanges() {
        XCTAssertEqual(GreenSpeed(stimp: 6), .verySlow)
        XCTAssertEqual(GreenSpeed(stimp: 7), .slow)
        XCTAssertEqual(GreenSpeed(stimp: 8), .slow)
        XCTAssertEqual(GreenSpeed(stimp: 9), .medium)
        XCTAssertEqual(GreenSpeed(stimp: 10), .medium)
        XCTAssertEqual(GreenSpeed(stimp: 11), .fast)
        XCTAssertEqual(GreenSpeed(stimp: 12), .fast)
        XCTAssertEqual(GreenSpeed(stimp: 13), .veryFast)
    }

    /// Rolls on 8 and 11 greens that follow distance ∝ Stimp × backswing².
    private func rolls(stimp: Double, count: Int) -> [SpeedPoint] {
        (0..<count).map { i in
            let back = 0.08 + 0.04 * Double(i)
            return SpeedPoint(backswing: back, distance: 6 * stimp * back * back, stimp: stimp)
        }
    }

    func testEstimatesASpeedWithNoPutts() throws {
        let chart = try XCTUnwrap(SpeedChart(points: rolls(stimp: 8, count: 6)))
        XCTAssertTrue(chart.isMeasured(.slow))
        XCTAssertFalse(chart.isMeasured(.veryFast))
        // No putts at 13.5, so it's scaled from the 8s: 13.5/8 as far.
        XCTAssertEqual(chart.distance(forBackswing: 0.2, stimp: 13.5), 6 * 13.5 * 0.04, accuracy: 0.01)
        // And a 20 ft putt needs a shorter stroke on the faster green.
        let d = 20 * 0.3048
        XCTAssertLessThan(chart.backswing(forDistance: d, stimp: 13.5), chart.backswing(forDistance: d, stimp: 8))
    }

    func testUsesOwnPuttsOnceThereAreEnough() throws {
        // The player's fast-green putts roll 20% shorter than Stimp alone predicts.
        var points = rolls(stimp: 8, count: 6)
        points += (0..<6).map { i in
            let back = 0.08 + 0.04 * Double(i)
            return SpeedPoint(backswing: back, distance: 0.8 * 6 * 11 * back * back, stimp: 11)
        }
        let chart = try XCTUnwrap(SpeedChart(points: points))
        XCTAssertTrue(chart.isMeasured(.fast))
        XCTAssertEqual(chart.distance(forBackswing: 0.2, stimp: 11), 0.8 * 6 * 11 * 0.04, accuracy: 0.01)
        XCTAssertEqual(chart.counts[.fast], 6)
    }

    func testRollsWithoutSpeedUseTheUsualSpeed() throws {
        let unknown = (0..<4).map { i in SpeedPoint(backswing: 0.1 + 0.05 * Double(i), distance: 1 + Double(i), stimp: nil) }
        let chart = try XCTUnwrap(SpeedChart(points: unknown))
        XCTAssertEqual(chart.usualStimp, SpeedChart.referenceStimp)
        XCTAssertTrue(chart.measured.isEmpty)
    }
}

final class LandmarkTests: XCTestCase {
    /// Rolls on a Stimp 10 green that follow distance ∝ Stimp × backswing².
    private func chart() throws -> SpeedChart {
        let points = (0..<8).map { i -> SpeedPoint in
            let back = 0.06 + 0.03 * Double(i)
            return SpeedPoint(backswing: back, distance: 6 * 10 * back * back, stimp: 10)
        }
        return try XCTUnwrap(SpeedChart(points: points))
    }

    private let notes = [
        LandmarkPoint(backswing: 0.10, landmark: .inside, stimp: 10),
        LandmarkPoint(backswing: 0.11, landmark: .inside, stimp: 10),
        LandmarkPoint(backswing: 0.18, landmark: .middle, stimp: 10),
        LandmarkPoint(backswing: 0.19, landmark: .middle, stimp: 10),
        LandmarkPoint(backswing: 0.27, landmark: .outside, stimp: 10),
    ]

    func testNeedsANote() {
        XCTAssertNil(LandmarkMap(points: []))
    }

    func testPicksTheClosestLandmarkUsed() throws {
        let map = try XCTUnwrap(LandmarkMap(points: notes))
        XCTAssertEqual(map.landmark(forBackswing: 0.105), .inside)
        XCTAssertEqual(map.landmark(forBackswing: 0.20), .middle)
        XCTAssertEqual(map.landmark(forBackswing: 0.30), .outside)
        // Inside-middle was never used, so it's never suggested.
        XCTAssertEqual(map.landmark(forBackswing: 0.14), .inside)
        XCTAssertEqual(map.counts[.medium], 5)
    }

    func testSameDistanceMovesInsideOnFasterGreens() throws {
        let chart = try chart(), map = try XCTUnwrap(LandmarkMap(points: notes))
        // A putt that needs a 0.16 m backswing on a 10 reaches the middle of the foot.
        let d = chart.distance(forBackswing: 0.16, stimp: 10)
        XCTAssertEqual(map.landmark(forDistance: d, stimp: 10, chart: chart), .middle)
        // On a 13.5 the same putt needs about 0.14 m, closer to the inside landmark.
        XCTAssertEqual(map.landmark(forDistance: d, stimp: 13.5, chart: chart), .inside)
        // On a 6 it needs about 0.21 m: still the middle, but farther back.
        XCTAssertEqual(map.landmark(forDistance: d, stimp: 6, chart: chart), .middle)
        XCTAssertGreaterThan(chart.backswing(forDistance: d, stimp: 6), 0.2)
    }
}

final class UsualRangeTests: XCTestCase {
    func testNeedsThreeSessions() {
        XCTAssertNil(Consistency.usualRange(of: [80, 82]))
    }

    func testIsAtLeastSixPointsWide() throws {
        let r = try XCTUnwrap(Consistency.usualRange(of: [80, 80, 80]))
        XCTAssertEqual(r.lowerBound, 77, accuracy: 1e-9)
        XCTAssertEqual(r.upperBound, 83, accuracy: 1e-9)
        XCTAssertEqual(Consistency.placement(of: 85, in: r), .above)
        XCTAssertEqual(Consistency.placement(of: 79, in: r), .within)
        XCTAssertEqual(Consistency.placement(of: 70, in: r), .below)
    }

    func testFollowsTheSpread() throws {
        let r = try XCTUnwrap(Consistency.usualRange(of: [60, 70, 80, 90, 100]))
        XCTAssertEqual(r.lowerBound, 80 - 200.0.squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(r.upperBound, 100, accuracy: 1e-9)
    }
}
