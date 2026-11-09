import HealthKit
import SwiftUI
import WatchKit

@main
struct PuttWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate
    @State private var model = PracticeModel.shared

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if model.isRunning {
                    PracticePager()
                } else {
                    StartView()
                }
            }
            .environment(model)
            // Bright fairway green: high contrast on the watch's black background.
            .tint(Color(red: 0.36, green: 0.80, blue: 0.58))
        }
    }
}

/// Tapping Start session on the phone opens this app with a golf workout.
/// Starting right away means the player looks down and sees Ready.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        DispatchQueue.main.async { PracticeModel.shared.start() }
    }
}
