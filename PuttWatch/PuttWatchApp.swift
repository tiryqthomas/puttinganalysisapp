import SwiftUI

@main
struct PuttWatchApp: App {
    @State private var model = PracticeModel()

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
