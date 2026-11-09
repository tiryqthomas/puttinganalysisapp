import Foundation
import HealthKit

/// Keeps the app running, and the motion sensors streaming, while the
/// player's wrist is down over the ball.
///
/// watchOS suspends ordinary apps when the wrist lowers. A workout session
/// is the supported way to stay active. Nothing is saved to Health: the
/// session is ended without a workout builder.
final class WorkoutKeeper: NSObject, HKWorkoutSessionDelegate {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?

    /// Starts a golf workout session if Health access allows it. The app
    /// still works without one while the screen stays on.
    func start() async {
        guard HKHealthStore.isHealthDataAvailable(), session == nil else { return }
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
            let config = HKWorkoutConfiguration()
            config.activityType = .golf
            config.locationType = .outdoor
            let s = try HKWorkoutSession(healthStore: store, configuration: config)
            s.delegate = self
            s.startActivity(with: Date())
            session = s
        } catch {
            session = nil
        }
    }

    func stop() {
        session?.end()
        session = nil
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        session = nil
    }
}
